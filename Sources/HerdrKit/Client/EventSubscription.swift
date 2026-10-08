import Darwin
import Foundation

/// One `events.subscribe` connection. `start` returns only after herdr acknowledges with
/// `subscription_started`; `run` then reports each pushed event until the stream ends.
package final class EventSubscription: Sendable {
    package let set: SubscriptionSet
    private let requestID: String
    private let connection: LineConnection

    private init(fd: Int32, requestID: String, set: SubscriptionSet) {
        self.connection = LineConnection(fd: fd)
        self.requestID = requestID
        self.set = set
    }

    /// Connects, subscribes and waits for the acknowledgement. Throws `server(.paneNotFound)`
    /// when a named pane is gone (herdr rejects the whole request), or `notRunning`.
    package static func start(path: String, set: SubscriptionSet, timeout: Duration) async throws -> EventSubscription {
        let request = RequestEnvelope(method: "events.subscribe", params: set.params)
        let line = try request.encodedLine()
        let fd = try await BlockingIO.run {
            let fd = try UnixSocket.connect(path: path)
            do {
                UnixSocket.setTimeout(fd, timeout)
                try UnixSocket.writeAll(fd, line)
                switch try IncomingLine(try UnixSocket.readLineExact(fd)) {
                case .result:
                    return fd
                case .error(_, let code, let message):
                    throw HerdrError.server(code, message: message)
                case .event:
                    throw HerdrError.unexpectedResponse("event before subscription_started")
                }
            } catch {
                Darwin.close(fd)
                throw error
            }
        }
        return EventSubscription(fd: fd, requestID: request.id, set: set)
    }

    /// Calls `onEvent` for each pushed event and returns why the stream ended:
    /// `server(.eventsLost)` when herdr dropped this subscriber, otherwise `disconnected` or an
    /// I/O error.
    package func run(onEvent: @Sendable (HerdrEvent) async -> Void) async -> HerdrError {
        do {
            for try await line in connection.lines {
                switch try? IncomingLine(line) {
                case .event(let event):
                    await onEvent(event)
                case .error(let id, let code, let message) where id == requestID:
                    connection.close()
                    return .server(code, message: message)
                default:
                    continue
                }
            }
            return .disconnected
        } catch let error as HerdrError {
            return error
        } catch {
            return .disconnected
        }
    }

    package func close() {
        connection.close()
    }
}

import Darwin
import Dispatch
import Foundation

/// A long-lived socket read with a GCD read source: the kernel wakes it only when bytes arrive,
/// so an idle connection costs nothing. Lines come out of `lines`; the stream ends with
/// `HerdrError.disconnected` on EOF. The fd is closed only in the source's cancel handler.
package final class LineConnection: Sendable {
    package let lines: AsyncThrowingStream<Data, any Error>
    private let source: any DispatchSourceRead

    package static let queue = DispatchQueue(label: "dev.shepherd.herdr.io", qos: .utility)

    /// Takes ownership of `fd`.
    package init(fd: Int32, maxLineLength: Int = LineBuffer.defaultMaxLineLength) {
        UnixSocket.setNonBlocking(fd)
        let (stream, continuation) = AsyncThrowingStream<Data, any Error>.makeStream()
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: Self.queue)
        let state = ReadState(maxLineLength: maxLineLength)

        source.setEventHandler {
            if let error = state.drain(fd: fd, into: continuation) {
                continuation.finish(throwing: error)
                source.cancel()
            }
        }
        source.setCancelHandler {
            Darwin.close(fd)
            continuation.finish(throwing: HerdrError.disconnected)
        }
        continuation.onTermination = { _ in source.cancel() }

        self.lines = stream
        self.source = source
        source.resume()
    }

    /// Closes the connection. Safe to call more than once.
    package func close() {
        source.cancel()
    }
}

/// Read buffers for one connection. Only ever touched from `LineConnection.queue`, which is
/// serial, hence the unchecked conformance.
private final class ReadState: @unchecked Sendable {
    private var buffer: LineBuffer
    private var chunk = [UInt8](repeating: 0, count: 64 * 1024)

    init(maxLineLength: Int) {
        buffer = LineBuffer(maxLineLength: maxLineLength)
    }

    /// Reads until the socket would block. Returns the error that ends the stream, if any.
    func drain(fd: Int32, into continuation: AsyncThrowingStream<Data, any Error>.Continuation) -> (any Error)? {
        while true {
            let count = Darwin.read(fd, &chunk, chunk.count)
            if count > 0 {
                do {
                    for line in try buffer.append(chunk[0..<count]) { continuation.yield(line) }
                } catch {
                    return error
                }
            } else if count == 0 {
                return HerdrError.disconnected
            } else {
                switch errno {
                case EINTR: continue
                case EAGAIN: return nil
                default: return HerdrError.io(errno)
                }
            }
        }
    }
}

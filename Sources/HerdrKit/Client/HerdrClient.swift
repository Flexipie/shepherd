import Darwin
import Foundation

/// Request/response calls to herdr. herdr serves one request per connection, so every call opens
/// its own: connect, write one line, read one line, close. The client holds no state and calls
/// may run in parallel.
public struct HerdrClient: Sendable {
    public struct Timeouts: Sendable {
        public var ping: Duration = .seconds(1)
        public var snapshot: Duration = .seconds(2)
        public var action: Duration = .seconds(5)

        public init() {}
    }

    public let socketPath: String
    public var timeouts: Timeouts

    public init(socketPath: String = HerdrSocket.defaultPath(), timeouts: Timeouts = Timeouts()) {
        self.socketPath = socketPath
        self.timeouts = timeouts
    }

    public func ping() async throws -> Pong {
        try await call("ping", params: NoParams(), as: Pong.self, timeout: timeouts.ping)
    }

    public func snapshot() async throws -> SessionSnapshot {
        try await call("session.snapshot", params: NoParams(), as: SnapshotResult.self, timeout: timeouts.snapshot).snapshot
    }

    /// Focuses the agent's pane in herdr, which also marks a finished agent as seen.
    public func focusAgent(paneID: String) async throws {
        _ = try await call("agent.focus", params: ["target": paneID], as: IgnoredResult.self, timeout: timeouts.action)
    }

    /// Switches herdr to the workspace.
    public func focusWorkspace(id: String) async throws {
        _ = try await call("workspace.focus", params: ["workspace_id": id], as: IgnoredResult.self, timeout: timeouts.action)
    }

    /// The agent's visible screen as plain text, its last `lines` lines (`agent.read`).
    public func readAgent(paneID: String, lines: Int) async throws -> String {
        let params = ReadParams(target: paneID, source: "visible", lines: lines, stripAnsi: true)
        return try await call("agent.read", params: params, as: ReadResult.self, timeout: timeouts.action).read.text
    }

    /// Presses keys in the agent's pane (`agent.send_keys`), using herdr's key names such as
    /// `"1"`, `"enter"` or `"esc"`. herdr refuses a pane that is not running a known agent.
    public func sendKeys(paneID: String, keys: [String]) async throws {
        _ = try await call("agent.send_keys", params: SendKeysParams(target: paneID, keys: keys), as: IgnoredResult.self,
                           timeout: timeouts.action)
    }

    /// Types `text` into the pane, then presses `keys` (`pane.send_input`). herdr pastes the text
    /// as one bracketed paste when the program asked for that, so it arrives whole.
    public func sendInput(paneID: String, text: String, keys: [String]) async throws {
        _ = try await call("pane.send_input", params: SendInputParams(paneID: paneID, text: text, keys: keys),
                           as: IgnoredResult.self, timeout: timeouts.action)
    }

    /// Sends one request and decodes its `result`.
    public func call<Params: Encodable & Sendable, Result: Decodable & Sendable>(
        _ method: String, params: Params, as type: Result.Type, timeout: Duration
    ) async throws -> Result {
        let request = RequestEnvelope(method: method, params: params)
        let line = try request.encodedLine()
        let path = socketPath
        let reply = try await BlockingIO.run {
            let fd = try UnixSocket.connect(path: path)
            defer { Darwin.close(fd) }
            UnixSocket.setTimeout(fd, timeout)
            try UnixSocket.writeAll(fd, line)
            return try UnixSocket.readLine(fd)
        }
        switch try IncomingLine(reply) {
        case .result(let id, let data):
            guard id == request.id else { throw HerdrError.unexpectedResponse("reply id \(id) for \(request.id)") }
            do {
                return try JSONDecoder().decode(ResultEnvelope<Result>.self, from: data).result
            } catch {
                throw HerdrError.unexpectedResponse("cannot decode \(method) result: \(error)")
            }
        case .error(_, let code, let message):
            throw HerdrError.server(code, message: message)
        case .event:
            throw HerdrError.unexpectedResponse("event on a request connection")
        }
    }

    private struct SnapshotResult: Decodable, Sendable {
        let snapshot: SessionSnapshot
    }

    private struct ReadParams: Encodable, Sendable {
        let target: String
        let source: String
        let lines: Int
        let stripAnsi: Bool

        enum CodingKeys: String, CodingKey {
            case target, source, lines
            case stripAnsi = "strip_ansi"
        }
    }

    private struct ReadResult: Decodable, Sendable {
        struct Read: Decodable, Sendable {
            let text: String
        }

        let read: Read
    }

    private struct SendKeysParams: Encodable, Sendable {
        let target: String
        let keys: [String]
    }

    private struct SendInputParams: Encodable, Sendable {
        let paneID: String
        let text: String
        let keys: [String]

        enum CodingKeys: String, CodingKey {
            case paneID = "pane_id"
            case text, keys
        }
    }
}

/// Runs blocking socket work on a GCD thread so it never ties up the cooperative pool.
package enum BlockingIO {
    package static func run<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(with: Result { try work() })
            }
        }
    }
}

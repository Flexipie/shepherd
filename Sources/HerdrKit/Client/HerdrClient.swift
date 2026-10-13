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
        /// herdr types a prompt, waits a moment, then presses Enter before it answers.
        public var prompt: Duration = .seconds(10)
        /// `git worktree add` and opening its workspace.
        public var worktree: Duration = .seconds(30)
        /// herdr answers `agent.start` once the agent is ready, waiting up to 30 seconds itself.
        public var start: Duration = .seconds(40)

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

    /// Submits a prompt to the agent (`agent.prompt`). herdr refuses a blocked agent
    /// (`agent_blocked`); answer those with keys or input instead.
    public func promptAgent(paneID: String, text: String) async throws {
        _ = try await call("agent.prompt", params: ["target": paneID, "text": text], as: IgnoredResult.self,
                           timeout: timeouts.prompt)
    }

    /// A checkout made by `worktree.create`: its workspace, the shell pane in it, and its branch.
    public struct CreatedWorktree: Sendable, Equatable {
        public let workspaceID: String
        public let rootPaneID: String
        public let branch: String?
    }

    /// Creates a git worktree from the workspace's repo and opens it as a new workspace
    /// (`worktree.create`). A nil branch lets herdr make one up.
    public func createWorktree(workspaceID: String, branch: String?) async throws -> CreatedWorktree {
        let params = WorktreeParams(workspaceID: workspaceID, branch: branch)
        let result = try await call("worktree.create", params: params, as: WorktreeResult.self, timeout: timeouts.worktree)
        return CreatedWorktree(workspaceID: result.workspace.workspaceID, rootPaneID: result.rootPane.paneID,
                               branch: result.worktree.branch)
    }

    /// Starts an agent in a shell pane (`agent.start`). herdr answers once the agent is ready
    /// for input. `name` must be unique, lowercase letters, digits, `-` and `_`.
    public func startAgent(name: String, kind: String, paneID: String, args: [String]) async throws {
        let params = StartParams(name: name, kind: kind, paneID: paneID, args: args)
        _ = try await call("agent.start", params: params, as: IgnoredResult.self, timeout: timeouts.start)
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

    private struct WorktreeParams: Encodable, Sendable {
        let workspaceID: String
        let branch: String?

        enum CodingKeys: String, CodingKey {
            case workspaceID = "workspace_id"
            case branch
        }
    }

    private struct WorktreeResult: Decodable, Sendable {
        struct Workspace: Decodable, Sendable {
            let workspaceID: String
            enum CodingKeys: String, CodingKey { case workspaceID = "workspace_id" }
        }

        struct Pane: Decodable, Sendable {
            let paneID: String
            enum CodingKeys: String, CodingKey { case paneID = "pane_id" }
        }

        struct Worktree: Decodable, Sendable {
            let branch: String?
        }

        let workspace: Workspace
        let rootPane: Pane
        let worktree: Worktree

        enum CodingKeys: String, CodingKey {
            case workspace, worktree
            case rootPane = "root_pane"
        }
    }

    private struct StartParams: Encodable, Sendable {
        let name: String
        let kind: String
        let paneID: String
        let args: [String]

        enum CodingKeys: String, CodingKey {
            case name, kind, args
            case paneID = "pane_id"
        }
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

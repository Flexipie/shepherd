import Darwin

/// Where agents come from. A source owns its connection, recovery and decoding, and publishes
/// `SourceUpdate`s in the herd model. Nothing outside a source knows how it gets its state.
@MainActor
public protocol AgentSource: AnyObject {
    var id: SourceID { get }
    /// Shown to the user, such as "herdr".
    var displayName: String { get }
    var capabilities: SourceCapabilities { get }
    /// Updates, starting after `start()`. Ends after `stop()`.
    var updates: AsyncStream<SourceUpdate> { get }

    func start()
    func stop() async

    /// Shows the agent to the user: focuses it in the source's UI and brings its app forward.
    func focus(_ agent: AgentID) async throws

    /// Shows the project: focuses it in the source's UI and brings its app forward. Only called
    /// when `capabilities` contains `.focusProject`.
    func focusProject(_ project: ProjectID) async throws

    /// The agent's last `lines` visible lines, as plain text. Only called when `capabilities`
    /// contains `.readOutput`, and only while a surface shows them.
    func read(_ agent: AgentID, lines: Int) async throws -> String

    /// Presses keys in the agent, such as `["1"]` or `["enter"]`. Only called when
    /// `capabilities` contains `.sendKeys`.
    func sendKeys(_ agent: AgentID, _ keys: [String]) async throws

    /// Types `text` into the agent and presses Return. Only called when `capabilities` contains
    /// `.sendText`.
    func sendText(_ agent: AgentID, _ text: String) async throws

    /// Starts a new turn: submits `text` as a prompt to an agent that is not waiting on a
    /// question. Only called when `capabilities` contains `.prompt`.
    func prompt(_ agent: AgentID, _ text: String) async throws

    /// Makes a checkout for the task, starts its agent there with `args`, sends its prompt, and
    /// returns the new agent. Only called when `capabilities` contains `.createWorktree` and
    /// `.startAgent`. A step that fails after an earlier one worked says what was left behind.
    func startTask(_ task: NewTask, args: [String]) async throws -> AgentID

    /// Pids of the apps the source's agents live in, such as the terminal hosting them
    /// (`TerminalLocator`). Used to tell whether the user is already looking at an agent.
    func hostApplicationPIDs() -> [pid_t]
}

extension AgentSource {
    public func focusProject(_ project: ProjectID) async throws {
        throw AgentSourceError.unsupported(.focusProject)
    }

    public func read(_ agent: AgentID, lines: Int) async throws -> String {
        throw AgentSourceError.unsupported(.readOutput)
    }

    public func sendKeys(_ agent: AgentID, _ keys: [String]) async throws {
        throw AgentSourceError.unsupported(.sendKeys)
    }

    public func sendText(_ agent: AgentID, _ text: String) async throws {
        throw AgentSourceError.unsupported(.sendText)
    }

    public func prompt(_ agent: AgentID, _ text: String) async throws {
        throw AgentSourceError.unsupported(.prompt)
    }

    public func startTask(_ task: NewTask, args: [String]) async throws -> AgentID {
        throw AgentSourceError.unsupported(.startAgent)
    }
}

public enum AgentSourceError: Error, Sendable, Equatable, CustomStringConvertible {
    case unknownSource(SourceID)
    case unsupported(SourceCapabilities)
    /// The source tried and failed, in words a person can read.
    case failed(String)

    public var description: String {
        switch self {
        case .unknownSource(let source): "\(source) is not connected"
        case .unsupported: "this agent's source cannot do that"
        case .failed(let message): message
        }
    }
}

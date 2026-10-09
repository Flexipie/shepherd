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

    /// Pids of the apps the source's agents live in (for herdr, the terminal hosting it). Used to
    /// tell whether the user is already looking at an agent.
    func hostApplicationPIDs() -> [pid_t]
}

extension AgentSource {
    public func focusProject(_ project: ProjectID) async throws {
        throw AgentSourceError.unsupported(.focusProject)
    }
}

public enum AgentSourceError: Error, Sendable, Equatable {
    case unknownSource(SourceID)
    case unsupported(SourceCapabilities)
}

import Observation

/// An agent's own session, as its source reported it: which agent wrote it, its id, and where
/// the agent was started. Enough for a reader to find the agent's own files.
public struct AgentSession: Sendable, Hashable {
    /// The agent kind that owns the session, such as `claude`.
    public let kind: String
    public let id: String
    /// The agent's working directory, when known.
    public let cwd: String?

    public init(kind: String, id: String, cwd: String? = nil) {
        self.kind = kind
        self.id = id
        self.cwd = cwd
    }
}

/// Reads how many tokens an agent's context holds from its session. The app's reader lives in
/// its own target, so modules decide when to read and never do the I/O themselves. nil when the
/// reader does not know this kind of session or found no turn yet.
@MainActor
public protocol AgentContextReader: AnyObject {
    func contextTokens(for session: AgentSession) async throws -> Int?
}

/// The context sizes read so far, by agent. A module writes it; row builders read it inside
/// observation tracking, so a row redraws when its size changes. Empty unless a module fills it.
@MainActor
@Observable
public final class AgentContextStore {
    public private(set) var tokens: [AgentID: Int] = [:]

    public init() {}

    public func set(_ value: Int?, for agent: AgentID) {
        guard tokens[agent] != value else { return }
        tokens[agent] = value
    }

    /// Drops every agent not in `agents`.
    public func keep(only agents: Set<AgentID>) {
        let gone = tokens.keys.filter { !agents.contains($0) }
        for agent in gone { tokens[agent] = nil }
    }

    public func removeAll() {
        guard !tokens.isEmpty else { return }
        tokens = [:]
    }
}

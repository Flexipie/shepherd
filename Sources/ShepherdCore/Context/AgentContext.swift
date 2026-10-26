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

/// What a reader found in an agent's session: how many tokens its context holds and the text of
/// its last message. Either is nil when the reader found none.
public struct AgentSessionReading: Sendable, Equatable {
    public let contextTokens: Int?
    public let finalMessage: String?

    public init(contextTokens: Int? = nil, finalMessage: String? = nil) {
        self.contextTokens = contextTokens
        self.finalMessage = finalMessage
    }
}

/// Reads an agent's context size and last message from its session. The app's reader lives in
/// its own target, so modules decide when to read and never do the I/O themselves. nil when the
/// reader does not know this kind of session or found no file.
@MainActor
public protocol AgentContextReader: AnyObject {
    func read(_ session: AgentSession) async throws -> AgentSessionReading?
}

/// The context sizes and last messages read so far, by agent. A module writes it; row builders
/// read it inside observation tracking, so a row redraws when either changes. Empty unless a
/// module fills it.
@MainActor
@Observable
public final class AgentContextStore {
    public private(set) var tokens: [AgentID: Int] = [:]
    public private(set) var finalMessages: [AgentID: String] = [:]

    public init() {}

    public func set(_ value: Int?, for agent: AgentID) {
        guard tokens[agent] != value else { return }
        tokens[agent] = value
    }

    public func set(finalMessage: String?, for agent: AgentID) {
        guard finalMessages[agent] != finalMessage else { return }
        finalMessages[agent] = finalMessage
    }

    /// Drops every agent not in `agents`.
    public func keep(only agents: Set<AgentID>) {
        for agent in tokens.keys where !agents.contains(agent) { tokens[agent] = nil }
        for agent in finalMessages.keys where !agents.contains(agent) { finalMessages[agent] = nil }
    }

    public func removeAll() {
        if !tokens.isEmpty { tokens = [:] }
        if !finalMessages.isEmpty { finalMessages = [:] }
    }
}

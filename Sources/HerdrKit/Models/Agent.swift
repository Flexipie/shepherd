import Foundation

/// An agent running in a pane.
public struct Agent: Sendable, Equatable, Identifiable, Decodable {
    /// The pane id; an agent is identified by the pane it runs in.
    public let id: String
    public let workspaceID: String
    public let tabID: String
    /// Changes when a different terminal occupies the pane id (for example after a herdr restart).
    public let terminalID: String?
    /// The detected agent kind, such as `claude` or `codex`.
    public let agent: String?
    /// A plugin-provided display name; herdr's sidebar prefers it.
    public let displayAgent: String?
    public let name: String?
    public let title: String?
    public let status: AgentStatus
    /// Bumps on every state transition.
    public let stateChangeSeq: UInt64
    /// Bumps when a working turn completes. herdr may send null.
    public let completionSeq: UInt64?
    public let focused: Bool
    /// Per-state label overrides published by plugins, keyed by status raw value.
    public let stateLabels: [String: String]
    public let tokens: [String: String]
    /// The pane's working directory.
    public let cwd: String?
    /// The agent's own session, when herdr detected one.
    public let session: Session?

    /// An agent's own session. herdr names its kind `id` when `value` is the agent's session id,
    /// such as a Claude Code session's.
    public struct Session: Sendable, Equatable, Decodable {
        /// The agent kind the session belongs to, such as `claude`.
        public let agent: String?
        public let kind: String?
        public let value: String?

        public init(agent: String? = nil, kind: String? = nil, value: String? = nil) {
            self.agent = agent
            self.kind = kind
            self.value = value
        }

        private enum CodingKeys: String, CodingKey { case agent, kind, value }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            agent = c.lenient(.agent)
            kind = c.lenient(.kind)
            value = c.lenient(.value)
        }
    }

    public init(id: String, workspaceID: String, tabID: String = "", terminalID: String? = nil,
                agent: String? = nil, displayAgent: String? = nil, name: String? = nil, title: String? = nil,
                status: AgentStatus, stateChangeSeq: UInt64 = 0, completionSeq: UInt64? = nil,
                focused: Bool = false, stateLabels: [String: String] = [:], tokens: [String: String] = [:],
                cwd: String? = nil, session: Session? = nil) {
        self.id = id
        self.workspaceID = workspaceID
        self.tabID = tabID
        self.terminalID = terminalID
        self.agent = agent
        self.displayAgent = displayAgent
        self.name = name
        self.title = title
        self.status = status
        self.stateChangeSeq = stateChangeSeq
        self.completionSeq = completionSeq
        self.focused = focused
        self.stateLabels = stateLabels
        self.tokens = tokens
        self.cwd = cwd
        self.session = session
    }

    /// The name to show, in the same order of preference as herdr's sidebar.
    public var displayName: String {
        displayAgent ?? name ?? agent ?? "agent"
    }

    /// The label for the current state, honouring plugin overrides.
    public var statusLabel: String {
        stateLabels[status.rawValue] ?? status.rawValue
    }

    private enum CodingKeys: String, CodingKey {
        case id = "pane_id", workspaceID = "workspace_id", tabID = "tab_id", terminalID = "terminal_id"
        case agent, displayAgent = "display_agent", name, title, status = "agent_status"
        case stateChangeSeq = "state_change_seq", completionSeq = "completion_seq", focused
        case stateLabels = "state_labels", tokens, cwd, session = "agent_session"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        workspaceID = try c.decode(String.self, forKey: .workspaceID)
        tabID = c.lenient(.tabID, default: "")
        terminalID = c.lenient(.terminalID)
        agent = c.lenient(.agent)
        displayAgent = c.lenient(.displayAgent)
        name = c.lenient(.name)
        title = c.lenient(.title)
        status = c.lenient(.status, default: .unknown)
        stateChangeSeq = c.lenient(.stateChangeSeq, default: 0)
        completionSeq = c.lenient(.completionSeq)
        focused = c.lenient(.focused, default: false)
        stateLabels = c.lenient(.stateLabels, default: [:])
        tokens = c.lenient(.tokens, default: [:])
        cwd = c.lenient(.cwd)
        session = c.lenient(.session)
    }
}

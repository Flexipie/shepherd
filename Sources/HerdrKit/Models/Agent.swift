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

    public init(id: String, workspaceID: String, tabID: String = "", terminalID: String? = nil,
                agent: String? = nil, displayAgent: String? = nil, name: String? = nil, title: String? = nil,
                status: AgentStatus, stateChangeSeq: UInt64 = 0, completionSeq: UInt64? = nil,
                focused: Bool = false, stateLabels: [String: String] = [:], tokens: [String: String] = [:]) {
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
        case stateLabels = "state_labels", tokens
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
    }
}

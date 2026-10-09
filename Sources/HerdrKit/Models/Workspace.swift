import Foundation

public struct Workspace: Sendable, Equatable, Identifiable, Decodable {
    public let id: String
    public let number: Int
    public let label: String
    public let focused: Bool
    public let activeTabID: String?
    public let agentStatus: AgentStatus
    /// Plugin-published tokens. Empty is normal: herdr leaves the field out when there are none
    /// and does not restore tokens after a restart.
    public let tokens: [String: String]

    public init(id: String, number: Int = 0, label: String = "", focused: Bool = false,
                activeTabID: String? = nil, agentStatus: AgentStatus = .idle, tokens: [String: String] = [:]) {
        self.id = id
        self.number = number
        self.label = label
        self.focused = focused
        self.activeTabID = activeTabID
        self.agentStatus = agentStatus
        self.tokens = tokens
    }

    private enum CodingKeys: String, CodingKey {
        case id = "workspace_id", number, label, focused, activeTabID = "active_tab_id"
        case agentStatus = "agent_status", tokens
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        number = c.lenient(.number, default: 0)
        label = c.lenient(.label, default: "")
        focused = c.lenient(.focused, default: false)
        activeTabID = c.lenient(.activeTabID)
        agentStatus = c.lenient(.agentStatus, default: .unknown)
        tokens = c.lenient(.tokens, default: [:])
    }
}

public struct Tab: Sendable, Equatable, Identifiable, Decodable {
    public let id: String
    public let workspaceID: String
    public let number: Int
    public let label: String
    public let focused: Bool
    public let agentStatus: AgentStatus

    private enum CodingKeys: String, CodingKey {
        case id = "tab_id", workspaceID = "workspace_id", number, label, focused, agentStatus = "agent_status"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        workspaceID = try c.decode(String.self, forKey: .workspaceID)
        number = c.lenient(.number, default: 0)
        label = c.lenient(.label, default: "")
        focused = c.lenient(.focused, default: false)
        agentStatus = c.lenient(.agentStatus, default: .unknown)
    }
}

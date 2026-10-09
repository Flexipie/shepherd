import Foundation

/// A terminal pane. It may or may not run an agent; agents are listed separately in
/// `SessionSnapshot.agents`, keyed by the same pane id.
public struct Pane: Sendable, Equatable, Identifiable, Decodable {
    public let id: String
    public let workspaceID: String
    public let tabID: String
    public let terminalID: String?
    public let focused: Bool
    public let agentStatus: AgentStatus
    public let title: String?
    public let tokens: [String: String]

    private enum CodingKeys: String, CodingKey {
        case id = "pane_id", workspaceID = "workspace_id", tabID = "tab_id", terminalID = "terminal_id"
        case focused, agentStatus = "agent_status", title, tokens
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        workspaceID = try c.decode(String.self, forKey: .workspaceID)
        tabID = c.lenient(.tabID, default: "")
        terminalID = c.lenient(.terminalID)
        focused = c.lenient(.focused, default: false)
        agentStatus = c.lenient(.agentStatus, default: .unknown)
        title = c.lenient(.title)
        tokens = c.lenient(.tokens, default: [:])
    }
}

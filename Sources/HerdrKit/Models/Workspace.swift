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
    /// The git checkout the workspace is in; nil outside git.
    public let worktree: Worktree?

    public init(id: String, number: Int = 0, label: String = "", focused: Bool = false,
                activeTabID: String? = nil, agentStatus: AgentStatus = .idle, tokens: [String: String] = [:],
                worktree: Worktree? = nil) {
        self.id = id
        self.number = number
        self.label = label
        self.focused = focused
        self.activeTabID = activeTabID
        self.agentStatus = agentStatus
        self.tokens = tokens
        self.worktree = worktree
    }

    private enum CodingKeys: String, CodingKey {
        case id = "workspace_id", number, label, focused, activeTabID = "active_tab_id"
        case agentStatus = "agent_status", tokens, worktree
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
        worktree = c.lenient(.worktree)
    }
}

/// A workspace's git checkout: the repo it belongs to, and whether it is the main checkout or a
/// linked worktree. Every checkout of one repo has the same `repoKey`.
public struct Worktree: Sendable, Equatable, Decodable {
    public let repoKey: String
    public let repoName: String
    /// False for the repo's main checkout.
    public let isLinked: Bool
    public let repoRoot: String?
    public let checkoutPath: String?

    public init(repoKey: String, repoName: String, isLinked: Bool = false, repoRoot: String? = nil, checkoutPath: String? = nil) {
        self.repoKey = repoKey
        self.repoName = repoName
        self.isLinked = isLinked
        self.repoRoot = repoRoot
        self.checkoutPath = checkoutPath
    }

    private enum CodingKeys: String, CodingKey {
        case repoKey = "repo_key", repoName = "repo_name", isLinked = "is_linked_worktree"
        case repoRoot = "repo_root", checkoutPath = "checkout_path"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        repoKey = try c.decode(String.self, forKey: .repoKey)
        repoName = c.lenient(.repoName, default: "")
        isLinked = c.lenient(.isLinked, default: false)
        repoRoot = c.lenient(.repoRoot)
        checkoutPath = c.lenient(.checkoutPath)
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

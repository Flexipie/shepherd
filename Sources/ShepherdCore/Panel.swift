/// What a module puts in the panel: a titled section of items. Values only; the app draws them.
public struct PanelSection: Sendable, Equatable, Identifiable {
    /// The module's id.
    public let id: String
    public let title: String
    public let items: [PanelItem]
    /// Shown when `items` is empty.
    public let emptyText: String

    public init(id: String, title: String, items: [PanelItem], emptyText: String) {
        self.id = id
        self.title = title
        self.items = items
        self.emptyText = emptyText
    }
}

public enum PanelItem: Sendable, Equatable {
    case agent(PanelAgentRow)
    case project(PanelProjectCard)
    case notice(String)
}

/// What choosing an item does.
public enum PanelAction: Sendable, Hashable {
    case jump(AgentID)
    case focusProject(ProjectID)
}

/// One agent, with its token lines styled.
public struct PanelAgentRow: Sendable, Equatable {
    public let agent: HerdAgent
    public let tokens: [[StyledToken]]
    /// False when the agent's source is not live: the row shows its last known state, dimmed.
    public let isLive: Bool
    /// nil when the source cannot do it.
    public let action: PanelAction?

    public init(agent: HerdAgent, tokens: [[StyledToken]] = [], isLive: Bool = true, action: PanelAction? = nil) {
        self.agent = agent
        self.tokens = tokens
        self.isLive = isLive
        self.action = action
    }
}

/// One project and its agents.
public struct PanelProjectCard: Sendable, Equatable {
    public let project: HerdProject
    public let tokens: [[StyledToken]]
    public let agents: [PanelAgentRow]
    public let isLive: Bool
    public let action: PanelAction?

    public init(project: HerdProject, tokens: [[StyledToken]] = [], agents: [PanelAgentRow], isLive: Bool = true,
                action: PanelAction? = nil) {
        self.project = project
        self.tokens = tokens
        self.agents = agents
        self.isLive = isLive
        self.action = action
    }
}

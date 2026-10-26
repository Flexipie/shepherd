/// The tabs at the top of the menu bar panel and the notch bar. Each section says which one it
/// sits on, so a new gadget needs no list here.
public enum PanelTab: String, Sendable, Hashable, CaseIterable {
    /// The needs-you queue and the projects: what the surfaces are for.
    case agents
    /// Usage, This Mac and other gadgets.
    case gadgets

    public var title: String {
        switch self {
        case .agents: "Agents"
        case .gadgets: "Gadgets"
        }
    }
}

/// What a module puts in the panel: a titled section of items. Values only; the app draws them.
public struct PanelSection: Sendable, Equatable, Identifiable {
    /// The module's id.
    public let id: String
    public let title: String
    public let items: [PanelItem]
    /// Shown when `items` is empty.
    public let emptyText: String
    /// The tab the section shows on.
    public let tab: PanelTab

    public init(id: String, title: String, items: [PanelItem], emptyText: String, tab: PanelTab = .agents) {
        self.id = id
        self.title = title
        self.items = items
        self.emptyText = emptyText
        self.tab = tab
    }
}

public enum PanelItem: Sendable, Equatable {
    case agent(PanelAgentRow)
    case project(PanelProjectCard)
    /// Two or more checkouts of one repo, under one header.
    case repo(PanelRepoCard)
    /// A gadget's card of meters and lines.
    case gadget(GadgetCard)
    case notice(String)
}

/// A gadget's card: a title, a thin bar per meter, then short lines. A gadget whose content fits
/// this shape needs no view of its own: its module returns cards and every surface draws them.
public struct GadgetCard: Sendable, Equatable, Identifiable {
    /// Unique within the section.
    public let id: String
    public let title: String
    /// Beside the title, quieter: a plan, a host.
    public let detail: String?
    public let meters: [UsageMeter]
    /// Short lines under the meters: balances, errors.
    public let lines: [String]
    /// The data is old, such as after a failed refresh: the card is dimmed.
    public let isStale: Bool

    public init(id: String, title: String, detail: String? = nil, meters: [UsageMeter] = [], lines: [String] = [],
                isStale: Bool = false) {
        self.id = id
        self.title = title
        self.detail = detail
        self.meters = meters
        self.lines = lines
        self.isStale = isStale
    }
}

extension GadgetCard {
    /// One account's plan usage: its name and plan, its limits, then its notes.
    public init(_ provider: UsageProvider) {
        self.init(id: provider.id, title: provider.name, detail: provider.plan, meters: provider.meters, lines: provider.notes,
                  isStale: provider.isStale)
    }
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
    /// How many tokens the agent's context holds, when a reader found out.
    public let contextTokens: Int?

    public init(agent: HerdAgent, tokens: [[StyledToken]] = [], isLive: Bool = true, action: PanelAction? = nil,
                contextTokens: Int? = nil) {
        self.agent = agent
        self.tokens = tokens
        self.isLive = isLive
        self.action = action
        self.contextTokens = contextTokens
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

/// The checkouts of one repo, main checkout first: one card with a sub-header per checkout.
public struct PanelRepoCard: Sendable, Equatable {
    /// Unique within the section.
    public let key: String
    public let name: String
    public let projects: [PanelProjectCard]

    public init(key: String, name: String, projects: [PanelProjectCard]) {
        self.key = key
        self.name = name
        self.projects = projects
    }
}

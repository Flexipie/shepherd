import Observation

/// What every module shares: the herd, what the user is looking at, the config, and the actions
/// it can trigger. Modules never open their own connections or see a source's own types.
@MainActor
public final class ModuleContext {
    public let store: HerdStore
    public let presence: Presence
    public let actions: any AgentActions
    public let config: ConfigStore

    public init(store: HerdStore, presence: Presence, actions: any AgentActions, config: ConfigStore = ConfigStore(fixed: .defaults)) {
        self.store = store
        self.presence = presence
        self.actions = actions
        self.config = config
    }

    /// Token lines for a project's or an agent's values: the config's layout for that section,
    /// else the source's, else every token on one line.
    public func tokenLines(_ section: TokenLayout.Section, values: [String: String], source: SourceID) -> [[StyledToken]] {
        TokenLayout.lines(section, values: values, layouts: [config.config.tokens, store.tokenLayouts[source]])
    }
}

/// Facts about the user's attention that the app observes and modules read.
@MainActor
@Observable
public final class Presence {
    /// Sources whose host app is frontmost, so the agent each has focused is on screen.
    public var frontmostSources: Set<SourceID> = []

    public init() {}

    /// Whether the user is probably looking at this agent right now.
    public func isLookingAt(_ agent: HerdAgent) -> Bool {
        agent.isFocusedInSource && frontmostSources.contains(agent.id.source)
    }
}

/// Actions modules can trigger.
@MainActor
public protocol AgentActions: AnyObject {
    /// Shows the agent: focuses it in its source (marking it seen) and brings its app forward.
    func jump(to agent: AgentID)

    /// Shows the project in its source and brings the source's app forward.
    func focusProject(_ project: ProjectID)
}

extension AgentActions {
    public func perform(_ action: PanelAction) {
        switch action {
        case .jump(let agent): jump(to: agent)
        case .focusProject(let project): focusProject(project)
        }
    }
}

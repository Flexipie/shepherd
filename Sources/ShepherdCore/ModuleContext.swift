import Observation

/// What every module shares: the herd, what the user is looking at, the config, and the actions
/// it can trigger. Modules never open their own connections or see a source's own types.
@MainActor
public final class ModuleContext {
    public let store: HerdStore
    public let presence: Presence
    public let actions: any AgentActions
    public let config: ConfigStore
    /// Posts system notifications; nil where there are none (tests, or before the app sets one).
    public let notifier: (any Notifier)?
    /// Reads plan usage limits; nil where there is no reader.
    public let usage: (any UsageReader)?
    /// Measures the Mac's CPU and memory; nil where there is no sampler.
    public let system: (any SystemSampler)?
    /// Reads an agent's context size from its session; nil where there is no reader.
    public let contextReader: (any AgentContextReader)?
    /// Context sizes by agent, filled by the module that reads them.
    public let agentContext = AgentContextStore()

    public init(store: HerdStore, presence: Presence, actions: any AgentActions, config: ConfigStore = ConfigStore(fixed: .defaults),
                notifier: (any Notifier)? = nil, usage: (any UsageReader)? = nil, system: (any SystemSampler)? = nil,
                contextReader: (any AgentContextReader)? = nil) {
        self.store = store
        self.presence = presence
        self.actions = actions
        self.config = config
        self.notifier = notifier
        self.usage = usage
        self.system = system
        self.contextReader = contextReader
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
    /// The surfaces showing the panel's content right now (the menu bar panel, the notch bar),
    /// and the tab each shows.
    public private(set) var visiblePanels: [String: PanelTab] = [:]

    public init() {}

    /// Whether any panel is open.
    public var isPanelVisible: Bool { !visiblePanels.isEmpty }

    /// Whether any open panel shows `tab`, so a module that reads something only while its
    /// section is on screen can read.
    public func isShowing(_ tab: PanelTab) -> Bool {
        visiblePanels.values.contains(tab)
    }

    /// Records the tab `surface` shows; nil when it is closed.
    public func setPanel(_ surface: String, showing tab: PanelTab?) {
        guard visiblePanels[surface] != tab else { return }
        visiblePanels[surface] = tab
    }

    /// Whether the user is probably looking at this agent right now.
    public func isLookingAt(_ agent: HerdAgent) -> Bool {
        agent.isFocusedInSource && frontmostSources.contains(agent.id.source)
    }
}

/// One system notification about an agent. Posting again for the same agent replaces it.
public struct AgentNotice: Sendable, Equatable {
    public let agent: HerdAgent
    public let reason: NotchItem.Reason
    /// Whether the notification offers Reply (the source can send text to the agent).
    public let canReply: Bool

    public init(agent: HerdAgent, reason: NotchItem.Reason, canReply: Bool) {
        self.agent = agent
        self.reason = reason
        self.canReply = canReply
    }
}

/// Posts and withdraws system notifications. The app's implementation also handles their Jump
/// and Reply buttons.
@MainActor
public protocol Notifier: AnyObject {
    func post(_ notice: AgentNotice)
    /// Removes the agent's notification, once it no longer needs the user.
    func withdraw(_ agent: AgentID)
}

/// Actions modules can trigger.
@MainActor
public protocol AgentActions: AnyObject {
    /// Shows the agent: focuses it in its source (marking it seen) and brings its app forward.
    func jump(to agent: AgentID)

    /// Shows the project in its source and brings the source's app forward.
    func focusProject(_ project: ProjectID)

    /// What the agent's source can do, so a surface offers only what works.
    func capabilities(of agent: AgentID) -> SourceCapabilities

    /// The agent's last visible lines, read once per call. Surfaces call it only while shown.
    func read(_ agent: AgentID, lines: Int) async throws -> String

    /// Presses keys in the agent, such as `["1"]` to pick a choice.
    func sendKeys(_ agent: AgentID, _ keys: [String]) async throws

    /// Types text into the agent and presses Return.
    func sendText(_ agent: AgentID, _ text: String) async throws

    /// Submits a prompt to an agent that is not waiting on a question.
    func prompt(_ agent: AgentID, _ text: String) async throws

    /// Starts a task (a checkout, an agent, its prompt) with the agent's args from config, and
    /// returns the new agent.
    func startTask(_ task: NewTask) async throws -> AgentID
}

extension AgentActions {
    public func perform(_ action: PanelAction) {
        switch action {
        case .jump(let agent): jump(to: agent)
        case .focusProject(let project): focusProject(project)
        }
    }
}

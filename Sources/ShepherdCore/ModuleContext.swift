import Observation

/// What every module shares: the herd, what the user is looking at, and the actions it can
/// trigger. Modules never open their own connections or see a source's own types.
@MainActor
public final class ModuleContext {
    public let store: HerdStore
    public let presence: Presence
    public let actions: any AgentActions

    public init(store: HerdStore, presence: Presence, actions: any AgentActions) {
        self.store = store
        self.presence = presence
        self.actions = actions
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
}

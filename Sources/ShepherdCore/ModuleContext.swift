import HerdrKit
import Observation

/// What every module shares: the live session, what the user is looking at, and the actions it
/// can trigger. Modules never open their own herdr connections.
@MainActor
public final class ModuleContext {
    public let store: SessionStore
    public let presence: Presence
    public let actions: any AgentActions

    public init(store: SessionStore, presence: Presence, actions: any AgentActions) {
        self.store = store
        self.presence = presence
        self.actions = actions
    }
}

/// Facts about the user's attention that the app observes and modules read.
@MainActor
@Observable
public final class Presence {
    /// The terminal running herdr is the frontmost app, so herdr's focused pane is on screen.
    public var terminalIsFrontmost = false

    public init() {}
}

/// Actions modules can trigger.
@MainActor
public protocol AgentActions: AnyObject {
    /// Focuses the agent's pane in herdr (marking it seen) and brings its terminal forward.
    func jump(to paneID: String)
}

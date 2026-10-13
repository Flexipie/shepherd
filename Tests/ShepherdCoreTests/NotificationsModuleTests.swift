import Foundation
import Testing
@testable import ShepherdCore
@testable import ShepherdModules

@MainActor
final class RecordingNotifier: Notifier {
    var posted: [AgentNotice] = []
    var withdrawn: [AgentID] = []
    func post(_ notice: AgentNotice) { posted.append(notice) }
    func withdraw(_ agent: AgentID) { withdrawn.append(agent) }
}

@MainActor
@Suite struct NotificationsModuleTests {
    let store = HerdStore()
    let presence = Presence()
    let notifier = RecordingNotifier()
    let source = StubSource("herdr")

    init() {
        source.capabilities = [.focus, .sendText]
        store.add(source)
    }

    func module(_ mode: ShepherdConfig.Notifications = .auto) -> NotificationsModule {
        let config = ConfigStore(fixed: ShepherdConfig(notifications: mode))
        return NotificationsModule(context: ModuleContext(store: store, presence: presence, actions: RecordingActions(),
                                                          config: config, notifier: notifier))
    }

    /// Agent a goes from working to `to`, as a live update.
    func change(to status: HerdStatus, from: HerdStatus? = .working, focused: Bool = false, ownAlerts: Bool = false) -> [HerdTransition] {
        let agent = herdAgent("herdr", "a", status, since: Date(), focused: focused)
        let transitions = [HerdTransition(agent: agent.id, from: from, to: status, at: Date())]
        store.apply(SourceUpdate(agents: [agent], state: .live, transitions: transitions, postsSystemAlerts: ownAlerts), from: "herdr")
        return transitions
    }

    @Test func blockedPostsWithReply() {
        let module = module()
        module.handle(change(to: .blocked))
        #expect(notifier.posted.map(\.agent.id.local) == ["a"])
        #expect(notifier.posted.first?.canReply == true)
        #expect(notifier.posted.first?.reason == .blocked)
    }

    @Test func leavingBlockedWithdraws() {
        let module = module()
        module.handle(change(to: .working, from: .blocked))
        #expect(notifier.withdrawn.map(\.local) == ["a"])
        #expect(notifier.posted.isEmpty)
    }

    @Test func quietWhileLookingAtTheAgent() {
        let module = module()
        presence.frontmostSources = ["herdr"]
        module.handle(change(to: .blocked, focused: true))
        #expect(notifier.posted.isEmpty)
    }

    @Test func onlyChangesSeenHappening() {
        let module = module()
        module.handle(change(to: .blocked, from: nil))
        module.handle(change(to: .done))
        #expect(notifier.posted.isEmpty)
    }

    @Test func autoDefersToASourceThatAlertsItself() {
        module().handle(change(to: .blocked, ownAlerts: true))
        #expect(notifier.posted.isEmpty)
        module(.on).handle(change(to: .blocked, ownAlerts: true))
        #expect(notifier.posted.count == 1)
    }

    @Test func offPostsNothing() {
        module(.off).handle(change(to: .blocked))
        #expect(notifier.posted.isEmpty)
    }

    @Test func notWhenTheSourceIsNotLive() {
        let module = module()
        let agent = herdAgent("herdr", "a", .blocked, since: Date())
        store.apply(SourceUpdate(agents: [agent], state: .stale("gap"),
                                 transitions: [HerdTransition(agent: agent.id, from: .working, to: .blocked, at: Date())]),
                    from: "herdr")
        module.handle(store.lastTransitions)
        #expect(notifier.posted.isEmpty)
    }
}

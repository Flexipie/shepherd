import Foundation
import Observation
import Testing
@testable import ShepherdCore
@testable import ShepherdModules

@MainActor
final class RecordingActions: AgentActions {
    var jumps: [AgentID] = []
    func jump(to agent: AgentID) { jumps.append(agent) }
}

@MainActor
@Suite struct ModuleTests {
    let store = HerdStore()
    let presence = Presence()
    var context: ModuleContext { ModuleContext(store: store, presence: presence, actions: RecordingActions()) }

    init() {
        store.add(StubSource("herdr"))
    }

    func show(_ agents: [HerdAgent], state: SourceState = .live) {
        store.apply(SourceUpdate(agents: agents, state: state), from: "herdr")
    }

    func agent(_ local: String, _ status: HerdStatus, focused: Bool = false) -> HerdAgent {
        herdAgent("herdr", local, status, since: Date(), focused: focused)
    }

    @Test func statusCountsWaitingAgentsAndDimsWhenNotLive() {
        let module = StatusModule(context: context)
        show([agent("a", .working), agent("b", .blocked), agent("c", .done)])
        #expect(module.status?.count == 2)
        #expect(module.status?.emphasis == .attention)
        show([agent("a", .working)])
        #expect(module.status?.count == nil)
        #expect(module.status?.emphasis == .normal)
        show([agent("b", .blocked)], state: .disconnected("herdr is not running"))
        #expect(module.status?.emphasis == .dimmed)
        #expect(module.status?.accessibilityLabel == "Shepherd: herdr is not running")
    }

    @Test func notchShowsBlockedUntilHandled() {
        let module = NotchModule(context: context)
        show([agent("a", .working), agent("b", .blocked), agent("c", .done)])
        #expect(module.notch?.agent.id.local == "b")
        #expect(module.notch?.reason == .blocked)
        #expect(module.notch?.others == 1)
        #expect(module.notch?.subtitle == "project 1 · needs you")
        show([agent("b", .working)])
        #expect(module.notch == nil)
    }

    @Test func notchStaysQuietForWhatYouAreLookingAt() {
        let module = NotchModule(context: context)
        presence.frontmostSources = ["herdr"]
        show([agent("b", .blocked, focused: true)])
        #expect(module.notch == nil)
        presence.frontmostSources = []
        #expect(module.notch?.agent.id.local == "b")
    }

    @Test func notchHidesAgentsOfSourcesThatAreNotLive() {
        let module = NotchModule(context: context)
        show([agent("b", .blocked)], state: .stale("fell behind herdr's events"))
        #expect(module.notch == nil)
    }

    @Test func finishedAgentShowsBrieflyThenOnlyInTheCount() async throws {
        NotchModule.briefDuration = .milliseconds(100)
        defer { NotchModule.briefDuration = .seconds(4) }
        let module = NotchModule(context: context)
        show([agent("c", .done)])
        #expect(module.notch == nil, "a done agent seen at launch is not news")

        module.startBriefWindows(for: [HerdTransition(agent: AgentID(source: "herdr", local: "c"), from: .working, to: .done, at: Date())])
        #expect(module.notch?.reason == .finished)
        try await Task.sleep(for: .milliseconds(300))
        #expect(module.notch == nil)
        #expect(StatusModule(context: context).status?.count == 1)
    }

    @Test func statusRedrawsWhenTheFirstSourceArrives() {
        let empty = HerdStore()
        let module = StatusModule(context: ModuleContext(store: empty, presence: presence, actions: RecordingActions()))
        let changed = Flag()
        let first = withObservationTracking { module.status } onChange: { changed.set() }
        #expect(first?.accessibilityLabel == "Shepherd: connecting")
        empty.add(StubSource("herdr"))
        empty.apply(SourceUpdate(agents: [], state: .live), from: "herdr")
        #expect(changed.value)
        #expect(module.status?.accessibilityLabel == "Shepherd: nothing needs you, 0 working")
    }
}

/// A thread-safe flag for observation callbacks.
final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var raised = false
    var value: Bool { lock.withLock { raised } }
    func set() { lock.withLock { raised = true } }
}

import Foundation
import Observation
import Testing
@testable import ShepherdCore
@testable import ShepherdModules

@MainActor
final class RecordingActions: AgentActions {
    var jumps: [AgentID] = []
    var projects: [ProjectID] = []
    func jump(to agent: AgentID) { jumps.append(agent) }
    func focusProject(_ project: ProjectID) { projects.append(project) }
    func capabilities(of agent: AgentID) -> SourceCapabilities { [.focus] }
    func read(_ agent: AgentID, lines: Int) async throws -> String { "" }
    func sendKeys(_ agent: AgentID, _ keys: [String]) async throws {}
    func sendText(_ agent: AgentID, _ text: String) async throws {}
    func prompt(_ agent: AgentID, _ text: String) async throws {}
    func startTask(_ task: NewTask) async throws -> AgentID { AgentID(source: "herdr", local: "new") }
}

@MainActor
@Suite(.serialized) struct ModuleTests {
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

    @Test func presenceTracksTheTabOfEachSurface() {
        #expect(!presence.isPanelVisible)
        #expect(!presence.isShowing(.agents))
        presence.setPanel("menu", showing: .agents)
        presence.setPanel("notch", showing: .gadgets)
        #expect(presence.isPanelVisible)
        #expect(presence.isShowing(.agents))
        #expect(presence.isShowing(.gadgets))
        presence.setPanel("menu", showing: .gadgets)
        #expect(!presence.isShowing(.agents))
        presence.setPanel("notch", showing: nil)
        #expect(presence.isShowing(.gadgets))
        presence.setPanel("menu", showing: nil)
        #expect(!presence.isPanelVisible)
        #expect(!presence.isShowing(.gadgets))
    }

    @Test func statusCountsWaitingAgentsAndDimsWhenNotLive() {
        let module = StatusModule(context: context)
        show([agent("a", .working), agent("b", .blocked), agent("c", .done)])
        #expect(module.status?.count == 2)
        #expect(module.status?.emphasis == .attention)
        #expect(module.status?.symbol == "pawprint.fill")
        #expect(module.status?.accessibilityLabel == "Shepherd: 1 blocked, 1 finished")
        show([agent("a", .working)])
        #expect(module.status?.count == nil)
        #expect(module.status?.emphasis == .normal)
        show([agent("b", .blocked)], state: .disconnected("herdr is not running"))
        #expect(module.status?.emphasis == .dimmed)
        #expect(module.status?.accessibilityLabel == "Shepherd: herdr is not running")
    }

    @Test func statusCountsFinishedAgentsWithoutOrange() {
        let module = StatusModule(context: context)
        show([agent("a", .done), agent("b", .done)])
        #expect(module.status?.count == 2)
        #expect(module.status?.emphasis == .normal)
        #expect(module.status?.symbol == "pawprint")
        #expect(module.status?.accessibilityLabel == "Shepherd: 2 finished")
    }

    func change(_ local: String, from: HerdStatus?, to: HerdStatus?) -> HerdTransition {
        HerdTransition(agent: AgentID(source: "herdr", local: local), from: from, to: to, at: Date())
    }

    /// Waits until the module's pill is shown (or hidden), or about five seconds.
    func waitFor(_ module: NotchModule, shown: Bool) async throws {
        for _ in 0..<500 where (module.notch != nil) != shown { try await Task.sleep(for: .milliseconds(10)) }
    }

    @Test func notchShowsANewBlockBrieflyThenThePaw() async throws {
        NotchModule.briefDuration = .milliseconds(100)
        defer { NotchModule.briefDuration = .seconds(4) }
        let module = NotchModule(context: context)
        show([agent("a", .working), agent("b", .blocked), agent("c", .done)])
        #expect(module.notch == nil, "a blocked agent seen at launch is not news")

        module.handle([change("b", from: .working, to: .blocked)])
        #expect(module.notch?.agent.id.local == "b")
        #expect(module.notch?.reason == .blocked)
        #expect(module.notch?.others == 1)
        #expect(module.notch?.subtitle == "project 1 · needs you")
        try await waitFor(module, shown: false)
        #expect(module.notch == nil)
        #expect(StatusModule(context: context).status?.count == 2, "the paw still counts it")
    }

    @Test func notchShowsAStillBlockedAgentOnceMore() async throws {
        NotchModule.briefDuration = .milliseconds(100)
        defer { NotchModule.briefDuration = .seconds(4) }
        var config = ShepherdConfig()
        config.notchEscalateAfter = 0.3
        let module = NotchModule(context: ModuleContext(store: store, presence: presence, actions: RecordingActions(),
                                                        config: ConfigStore(fixed: config)))
        show([agent("b", .blocked)])
        module.handle([change("b", from: .working, to: .blocked)])
        try await waitFor(module, shown: false)
        try await waitFor(module, shown: true)
        #expect(module.notch?.reason == .blocked)
        try await waitFor(module, shown: false)
        try await Task.sleep(for: .milliseconds(500))
        #expect(module.notch == nil, "nothing after the second time")

        module.handle([change("b", from: .blocked, to: .working), change("b", from: .working, to: .blocked)])
        #expect(module.notch != nil, "blocking again starts over")
        module.handle([change("b", from: .blocked, to: .working)])
        try await Task.sleep(for: .milliseconds(500))
        #expect(module.notch == nil, "unblocking cancels the second time")
    }

    @Test func notchIgnoresScreenReadings() {
        let module = NotchModule(context: context)
        let read = HerdAgent(id: AgentID(source: "herdr", local: "b"), kind: "claude", name: "agent b",
                             projectID: ProjectID(source: "herdr", local: "p1"), project: "project 1",
                             status: .blocked, since: nil, isInferred: true)
        show([read])
        module.handle([change("b", from: .working, to: .blocked)])
        #expect(module.notch == nil)
    }

    @Test func notchStaysQuietForWhatYouAreLookingAt() {
        let module = NotchModule(context: context)
        presence.frontmostSources = ["herdr"]
        show([agent("b", .blocked, focused: true)])
        module.handle([change("b", from: .working, to: .blocked)])
        #expect(module.notch == nil)
        presence.frontmostSources = []
        #expect(module.notch?.agent.id.local == "b")
    }

    @Test func notchHidesAgentsOfSourcesThatAreNotLive() {
        let module = NotchModule(context: context)
        show([agent("b", .blocked)], state: .stale("fell behind herdr's events"))
        module.handle([change("b", from: .working, to: .blocked)])
        #expect(module.notch == nil)
    }

    @Test func finishedAgentShowsBrieflyThenOnlyInTheCount() async throws {
        NotchModule.briefDuration = .milliseconds(100)
        defer { NotchModule.briefDuration = .seconds(4) }
        let module = NotchModule(context: context)
        show([agent("c", .done)])
        #expect(module.notch == nil, "a done agent seen at launch is not news")

        module.handle([change("c", from: .working, to: .done)])
        #expect(module.notch?.reason == .finished)
        try await waitFor(module, shown: false)
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

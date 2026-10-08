import Foundation
import HerdrKit
import Testing
@testable import ShepherdCore
@testable import ShepherdModules

@MainActor
final class RecordingActions: AgentActions {
    var jumps: [String] = []
    func jump(to paneID: String) { jumps.append(paneID) }
}

@MainActor
@Suite struct ModuleTests {
    let store = SessionStore(client: HerdrClient(socketPath: "/tmp/unused.sock"))
    let presence = Presence()
    var context: ModuleContext { ModuleContext(store: store, presence: presence, actions: RecordingActions()) }

    func agent(_ id: String, _ status: AgentStatus, seq: UInt64 = 1) -> Agent {
        Agent(id: id, workspaceID: "w1", terminalID: "t-\(id)", agent: "claude", status: status, stateChangeSeq: seq)
    }

    /// Feeds the store a snapshot, as the engine would.
    func show(_ agents: [Agent], focused: String? = nil, connection: ConnectionState = .live, transitions: [Transition] = []) {
        let snapshot = SessionSnapshot(focusedPaneID: focused, workspaces: [Workspace(id: "w1", label: "workspace 1")], agents: agents)
        var tracker = TransitionTracker()
        _ = tracker.apply(snapshot, at: Date(), continuity: .continuous)
        store.apply(SessionUpdate(session: Session(snapshot: snapshot, tracker: tracker), connection: connection,
                                  compatibility: .matched, transitions: transitions))
    }

    @Test func statusCountsWaitingAgentsAndDimsWhenNotLive() {
        let module = StatusModule(context: context)
        show([agent("a", .working), agent("b", .blocked), agent("c", .done)])
        #expect(module.status?.count == 2)
        #expect(module.status?.emphasis == .attention)
        show([agent("a", .working)])
        #expect(module.status?.count == nil)
        #expect(module.status?.emphasis == .normal)
        show([agent("b", .blocked)], connection: .disconnected("herdr is not running"))
        #expect(module.status?.emphasis == .dimmed)
        #expect(module.status?.count == nil)
    }

    @Test func notchShowsBlockedUntilHandled() {
        let module = NotchModule(context: context)
        show([agent("a", .working), agent("b", .blocked), agent("c", .done)])
        #expect(module.notch?.agent.id == "b")
        #expect(module.notch?.reason == .blocked)
        #expect(module.notch?.others == 1)
        #expect(module.notch?.subtitle == "workspace 1 · needs you")
        show([agent("b", .working, seq: 2)])
        #expect(module.notch == nil)
    }

    @Test func notchStaysQuietForWhatYouAreLookingAt() {
        let module = NotchModule(context: context)
        presence.terminalIsFrontmost = true
        show([agent("b", .blocked)], focused: "b")
        #expect(module.notch == nil)
        presence.terminalIsFrontmost = false
        #expect(module.notch?.agent.id == "b")
    }

    @Test func notchHidesWhenNotLive() {
        let module = NotchModule(context: context)
        show([agent("b", .blocked)], connection: .stale("fell behind herdr's events"))
        #expect(module.notch == nil)
    }

    @Test func finishedAgentShowsBrieflyThenOnlyInTheCount() async throws {
        NotchModule.briefDuration = .milliseconds(100)
        defer { NotchModule.briefDuration = .seconds(4) }
        let module = NotchModule(context: context)
        show([agent("c", .done)])
        #expect(module.notch == nil, "a done agent seen at launch is not news")

        module.startBriefWindows(for: [Transition(paneID: "c", kind: .changed, from: .working, to: .done, observedAt: Date())])
        #expect(module.notch?.reason == .finished)
        try await Task.sleep(for: .milliseconds(300))
        #expect(module.notch == nil)
        #expect(StatusModule(context: context).status?.count == 1)
    }
}

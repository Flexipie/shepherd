import Foundation
import ShepherdCore
import Testing
@testable import TmuxSource

@Suite struct PaneTrackerTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    func pane(_ status: HerdStatus, seen: Date? = nil, read: Date? = nil, path: String = "/work/app",
              paneID: String = "%1") -> PaneObservation {
        PaneObservation(key: PaneObservation.key(socket: "/tmp/s", paneID: paneID), socket: "/tmp/s", paneID: paneID,
                        windowID: "@0", session: "w", kind: "claude", path: path, isFocused: false, status: status,
                        workingSeen: status == .working ? (seen ?? start) : nil, readAt: read)
    }

    @Test func aKeyIsTheReportIdentityFormat() {
        #expect(PaneObservation.key(socket: "/tmp/s", paneID: "%3") == "tmux:/tmp/s:%3")
    }

    @Test func existingPanesAreTheBaselineAndAnnounceNothing() {
        var tracker = PaneTracker()
        let outcome = tracker.apply([pane(.blocked)], at: start)
        #expect(outcome.agents.map(\.status) == [.blocked])
        #expect(outcome.transitions.isEmpty)
    }

    @Test func aPromptShowsAtOnce() {
        var tracker = PaneTracker()
        _ = tracker.apply([pane(.idle)], at: start)
        let outcome = tracker.apply([pane(.blocked)], at: start.addingTimeInterval(0.1))
        #expect(outcome.agents.first?.status == .blocked)
        #expect(outcome.transitions.map(\.to) == [.blocked])
        #expect(outcome.transitions.map(\.from) == [.idle])
    }

    @Test func aChangeToWorkingWaitsForTwoSeconds() {
        var tracker = PaneTracker()
        _ = tracker.apply([pane(.idle)], at: start)
        let early = tracker.apply([pane(.working, seen: start.addingTimeInterval(1))], at: start.addingTimeInterval(1))
        #expect(early.agents.first?.status == .idle)
        #expect(early.transitions.isEmpty)
        // The clock starts when the new state was first read, so it settles two seconds after that.
        #expect(early.nextDeadline == start.addingTimeInterval(3))

        let settled = tracker.apply([pane(.working, seen: start.addingTimeInterval(3.5))], at: start.addingTimeInterval(3.5))
        #expect(settled.agents.first?.status == .working)
        #expect(settled.transitions.map(\.to) == [.working])
        #expect(settled.transitions.first?.at == start.addingTimeInterval(1))
    }

    @Test func aRedrawThatShowsNeitherMarkerDoesNotFlap() {
        var tracker = PaneTracker()
        _ = tracker.apply([pane(.working)], at: start)
        _ = tracker.apply([pane(.unknown, seen: nil)], at: start.addingTimeInterval(0.5))
        let back = tracker.apply([pane(.working, seen: start.addingTimeInterval(1))], at: start.addingTimeInterval(1))
        #expect(back.transitions.isEmpty)
        #expect(back.agents.first?.status == .working)
    }

    // The last read that showed the state with nothing else pending, so a merged row can tell a turn
    // that ended inside the settle time (#118). A read back before a change settled waits for it too.
    @Test func confirmedIsTheLastReadThatShowedTheStateHeld() {
        var tracker = PaneTracker()
        _ = tracker.apply([pane(.idle, read: start)], at: start)
        let steady = tracker.apply([pane(.idle, read: start.addingTimeInterval(0.5))], at: start.addingTimeInterval(0.5))
        #expect(steady.agents.first?.confirmed == start.addingTimeInterval(0.5))
        let one = start.addingTimeInterval(1), back = start.addingTimeInterval(1.5)
        _ = tracker.apply([pane(.working, seen: one, read: one)], at: one)
        let early = tracker.apply([pane(.idle, read: back)], at: back)
        #expect(early.agents.first?.confirmed == start.addingTimeInterval(0.5))
        #expect(early.nextDeadline == start.addingTimeInterval(3.5))
        let held = tracker.apply([pane(.idle, read: back)], at: start.addingTimeInterval(3.5))
        #expect(held.transitions.isEmpty)
        #expect(held.agents.first?.since == Since(start, .exact))
        #expect(held.agents.first?.confirmed == back)
    }

    @Test func aStateBackForOneReadIsNotConfirmed() {
        var tracker = PaneTracker()
        _ = tracker.apply([pane(.idle, read: start)], at: start)
        let times = [1, 1.5, 1.6, 3.6].map { start.addingTimeInterval($0) }
        _ = tracker.apply([pane(.working, seen: times[0], read: times[0])], at: times[0])
        _ = tracker.apply([pane(.idle, read: times[1])], at: times[1])
        _ = tracker.apply([pane(.working, seen: times[2], read: times[2])], at: times[2])
        let later = tracker.apply([pane(.working, seen: times[3], read: times[3])], at: times[3])
        #expect(later.agents.first?.status == .working)
        #expect(later.agents.first?.since == Since(times[2], .exact))
        #expect(later.agents.first?.confirmed == times[3])
    }

    @Test func workingGoesStaleWhenNoReadHasSeenIt() {
        var tracker = PaneTracker()
        _ = tracker.apply([pane(.working)], at: start)
        let later = start.addingTimeInterval(PaneTracker.quietLimit + 1)
        let pending = tracker.apply([pane(.working)], at: later)
        #expect(pending.agents.first?.status == .working)
        #expect(pending.nextDeadline == later.addingTimeInterval(PaneTracker.settle))

        let outcome = tracker.apply([pane(.working)], at: later.addingTimeInterval(PaneTracker.settle))
        #expect(outcome.agents.first?.status == .unknown)
        #expect(outcome.transitions.map(\.to) == [.unknown])
    }

    @Test func aPaneThatWentAwayCarriesWhatItWasAndItsFolder() {
        var tracker = PaneTracker()
        _ = tracker.apply([pane(.blocked, path: "/work/app")], at: start)
        let outcome = tracker.apply([], at: start.addingTimeInterval(5))
        #expect(outcome.agents.isEmpty)
        #expect(outcome.projects.isEmpty)
        let gone = outcome.transitions.first
        #expect(gone?.from == .blocked)
        #expect(gone?.to == nil)
        #expect(gone?.kind == "claude")
        #expect(gone?.project == "app")
    }

    @Test func agentsAreInferredAndProjectsFollowTheFolder() {
        var tracker = PaneTracker()
        let outcome = tracker.apply([pane(.idle, paneID: "%1"), pane(.idle, paneID: "%2")], at: start)
        #expect(outcome.agents.allSatisfy { $0.isInferred })
        #expect(outcome.agents.map(\.id.source) == ["tmux", "tmux"])
        #expect(outcome.projects.count == 1)
        #expect(outcome.projects.first?.path == "/work/app")
        #expect(outcome.projects.first?.isInferred == true)
    }

    @Test func aPaneWithNoFolderHasNoProject() {
        var tracker = PaneTracker()
        let outcome = tracker.apply([pane(.idle, path: "")], at: start)
        #expect(outcome.agents.first?.projectID == nil)
        #expect(outcome.projects.isEmpty)
    }
}

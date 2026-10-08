import Foundation
import Testing
@testable import HerdrKit

@Suite struct TransitionTrackerTests {
    let t0 = Date(timeIntervalSince1970: 1000)
    let t1 = Date(timeIntervalSince1970: 1060)

    func snap(_ agents: Agent...) -> SessionSnapshot { SessionSnapshot(agents: agents) }
    func agent(_ id: String, _ status: AgentStatus, seq: UInt64, completion: UInt64? = nil, terminal: String = "t1") -> Agent {
        Agent(id: id, workspaceID: "w1", terminalID: terminal, status: status, stateChangeSeq: seq, completionSeq: completion)
    }
    func agent(_ status: AgentStatus, seq: UInt64, completion: UInt64? = nil, terminal: String = "t1") -> Agent {
        agent("w1:p1", status, seq: seq, completion: completion, terminal: terminal)
    }

    @Test func firstSnapshotIsABaseline() {
        var tracker = TransitionTracker()
        #expect(tracker.apply(snap(agent(.working, seq: 3)), at: t0, continuity: .continuous).isEmpty)
        #expect(tracker.since("w1:p1") == StateSince(t0, .noLaterThan))
    }

    @Test func observedChangeIsExact() {
        var tracker = TransitionTracker()
        _ = tracker.apply(snap(agent(.working, seq: 3)), at: t0, continuity: .continuous)
        let transitions = tracker.apply(snap(agent(.blocked, seq: 4)), at: t1, continuity: .continuous)
        #expect(transitions.map(\.kind) == [.changed])
        #expect(transitions.first?.from == .working)
        #expect(transitions.first?.to == .blocked)
        #expect(transitions.first?.missedChanges == 0)
        #expect(tracker.since("w1:p1") == StateSince(t1, .exact))
    }

    @Test func seqJumpRevealsMissedChangesWithSameStatus() {
        var tracker = TransitionTracker()
        _ = tracker.apply(snap(agent(.working, seq: 3, completion: 1)), at: t0, continuity: .continuous)
        let transitions = tracker.apply(snap(agent(.working, seq: 5, completion: 2)), at: t1, continuity: .continuous)
        #expect(transitions.first?.missedChanges == 1)
        #expect(transitions.first?.completedTurns == 1)
    }

    @Test func changeAfterGapIsOnlyNoLaterThan() {
        var tracker = TransitionTracker()
        _ = tracker.apply(snap(agent(.working, seq: 3)), at: t0, continuity: .continuous)
        _ = tracker.apply(snap(agent(.done, seq: 4)), at: t1, continuity: .afterGap)
        #expect(tracker.since("w1:p1") == StateSince(t1, .noLaterThan))
    }

    @Test func noChangeAcrossGapKeepsEarlierTime() {
        var tracker = TransitionTracker()
        _ = tracker.apply(snap(agent(.working, seq: 3)), at: t0, continuity: .continuous)
        _ = tracker.apply(snap(agent(.blocked, seq: 4)), at: t0, continuity: .continuous)
        #expect(tracker.apply(snap(agent(.blocked, seq: 4)), at: t1, continuity: .afterGap).isEmpty)
        #expect(tracker.since("w1:p1") == StateSince(t0, .exact))
    }

    @Test func resetSeqOrNewTerminalStartsOver() {
        var tracker = TransitionTracker()
        _ = tracker.apply(snap(agent(.working, seq: 9)), at: t0, continuity: .continuous)
        #expect(tracker.apply(snap(agent(.idle, seq: 1)), at: t1, continuity: .continuous).isEmpty)
        #expect(tracker.since("w1:p1") == StateSince(t1, .noLaterThan))
        #expect(tracker.apply(snap(agent(.working, seq: 2, terminal: "t2")), at: t1, continuity: .continuous).isEmpty)
    }

    @Test func appearedAndClosed() {
        var tracker = TransitionTracker()
        _ = tracker.apply(snap(agent(.working, seq: 1)), at: t0, continuity: .continuous)
        let appeared = tracker.apply(snap(agent(.working, seq: 1), agent("w1:p2", .idle, seq: 1)), at: t1, continuity: .continuous)
        #expect(appeared.map(\.kind) == [.appeared])
        #expect(tracker.since("w1:p2") == StateSince(t1, .exact))
        let closed = tracker.apply(snap(agent("w1:p2", .idle, seq: 1)), at: t1, continuity: .continuous)
        #expect(closed.map(\.kind) == [.closed])
        #expect(tracker.since("w1:p1") == nil)
    }

    @Test func newAgentAfterGapIsNotClaimedAsJustAppeared() {
        var tracker = TransitionTracker()
        _ = tracker.apply(snap(), at: t0, continuity: .continuous)
        #expect(tracker.apply(snap(agent(.blocked, seq: 4)), at: t1, continuity: .afterGap).isEmpty)
        #expect(tracker.since("w1:p1")?.precision == .noLaterThan)
    }

    @Test func needsYouOrdersBlockedFirstThenLongestWaiting() {
        var tracker = TransitionTracker()
        let early = Date(timeIntervalSince1970: 10)
        _ = tracker.apply(snap(agent("a", .working, seq: 1), agent("b", .working, seq: 1), agent("c", .working, seq: 1)),
                          at: early, continuity: .continuous)
        _ = tracker.apply(snap(agent("a", .done, seq: 2), agent("b", .working, seq: 1), agent("c", .working, seq: 1)),
                          at: t0, continuity: .continuous)
        let latest = snap(agent("a", .done, seq: 2), agent("b", .done, seq: 2), agent("c", .blocked, seq: 2))
        _ = tracker.apply(latest, at: t1, continuity: .continuous)
        let session = Session(snapshot: latest, tracker: tracker)
        #expect(session.needsYou.map(\.id) == ["c", "a", "b"])
        #expect(session.workingCount == 0)
    }
}

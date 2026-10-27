import Foundation
import ReportKit
import ShepherdCore
import Testing
@testable import ReportSource

@Suite struct ReportTrackerTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    let id = AgentID(source: "report", local: "demo")

    func report(_ status: ReportFile.Status, at time: Date, key: String = "demo", cwd: String? = "/work/app",
                message: String? = nil, question: String? = nil) -> ReportFile {
        ReportFile(agent: key, status: status, message: message, question: question, kind: "claude", cwd: cwd, updatedAt: time)
    }

    /// "from>to" for each transition, with "-" for a missing side.
    func edges(_ transitions: [HerdTransition]) -> [String] {
        transitions.map { "\($0.from?.rawValue ?? "-")>\($0.to?.rawValue ?? "-")" }
    }

    /// A tracker past its baseline, with `reports` as the first read.
    func started(_ reports: [ReportFile], at time: Date) -> ReportTracker {
        var tracker = ReportTracker()
        _ = tracker.apply(reports, at: time)
        return tracker
    }

    @Test func aHookSessionKeyGivesTheAgentItsSession() {
        var tracker = ReportTracker()
        let outcome = tracker.apply([report(.working, at: t0, key: "session:abc-123"), report(.idle, at: t0)], at: t0)
        #expect(outcome.agents.map(\.session) == [nil, AgentSession(kind: "claude", id: "abc-123", cwd: "/work/app")])
    }

    @Test func theFirstReadIsTheBaselineAndEmitsNothing() {
        var tracker = ReportTracker()
        let outcome = tracker.apply([report(.working, at: t0)], at: t0)
        #expect(outcome.transitions.isEmpty)
        #expect(outcome.agents.map(\.status) == [.working])
    }

    @Test func aNewAgentIsATransitionFromNothing() {
        var tracker = started([], at: t0)
        let outcome = tracker.apply([report(.working, at: t0)], at: t0)
        #expect(outcome.transitions == [HerdTransition(agent: id, kind: "claude", project: "app", from: nil, to: .working, at: t0)])
    }

    @Test func aStatusChangeIsATransitionAndAChangeOfMessageIsNot() {
        var tracker = started([report(.working, at: t0)], at: t0)
        let t1 = t0.addingTimeInterval(10)
        let blocked = tracker.apply([report(.blocked, at: t1, question: "Ship?")], at: t1)
        #expect(edges(blocked.transitions) == ["working>blocked"])

        let t2 = t0.addingTimeInterval(20)
        let same = tracker.apply([report(.blocked, at: t2, question: "Ship it?")], at: t2)
        #expect(same.transitions.isEmpty)
        #expect(same.agents.first?.question == "Ship it?")
    }

    @Test func sinceIsTheReportsTimeAndIsKeptWhileTheStatusIsUnchanged() {
        var tracker = started([], at: t0)
        _ = tracker.apply([report(.working, at: t0)], at: t0)
        let t1 = t0.addingTimeInterval(60)
        let again = tracker.apply([report(.working, at: t1, message: "step 2")], at: t1)
        #expect(again.agents.first?.since == Since(t0, .exact))

        let t2 = t0.addingTimeInterval(120)
        let idle = tracker.apply([report(.idle, at: t2)], at: t2)
        #expect(idle.agents.first?.since == Since(t2, .exact))
    }

    @Test func aClosedReportRemovesTheAgentAndItsFile() {
        var tracker = started([report(.working, at: t0)], at: t0)
        let t1 = t0.addingTimeInterval(5)
        let outcome = tracker.apply([report(.closed, at: t1)], at: t1)
        #expect(outcome.agents.isEmpty)
        #expect(outcome.expired == ["demo"])
        #expect(outcome.transitions == [HerdTransition(agent: id, kind: "claude", project: "app", from: .working, to: nil, at: t1)])
    }

    @Test func aWorkingReportGoesUnknownAtItsDeadlineNotBefore() {
        var tracker = started([report(.working, at: t0)], at: t0)
        let before = tracker.apply([report(.working, at: t0)], at: t0.addingTimeInterval(14 * 60))
        #expect(before.agents.first?.status == .working)
        #expect(before.nextDeadline == t0.addingTimeInterval(15 * 60))

        let quiet = t0.addingTimeInterval(15 * 60)
        let outcome = tracker.apply([report(.working, at: t0)], at: quiet)
        #expect(outcome.agents.first?.status == .unknown)
        #expect(outcome.agents.first?.since == Since(quiet, .exact))
        #expect(edges(outcome.transitions) == ["working>unknown"])
        #expect(outcome.nextDeadline == nil)
    }

    @Test func aBlockedReportExpiresAfterADayAndIsDeleted() {
        var tracker = started([report(.blocked, at: t0)], at: t0)
        let later = tracker.apply([report(.blocked, at: t0)], at: t0.addingTimeInterval(24 * 60 * 60 - 1))
        #expect(later.agents.map(\.status) == [.blocked])
        #expect(later.nextDeadline == t0.addingTimeInterval(24 * 60 * 60))

        let expiry = t0.addingTimeInterval(24 * 60 * 60)
        let outcome = tracker.apply([report(.blocked, at: t0)], at: expiry)
        #expect(outcome.agents.isEmpty)
        #expect(outcome.expired == ["demo"])
        #expect(outcome.transitions.map(\.to) == [nil])
        // The file is still there until it is deleted: the next read must not announce it again.
        let again = tracker.apply([report(.blocked, at: t0)], at: expiry.addingTimeInterval(1))
        #expect(again.transitions.isEmpty)
        #expect(again.agents.isEmpty)
    }

    @Test func aDoneReportOlderThanADayIsNotShownWhenFirstRead() {
        var tracker = started([], at: t0)
        let old = report(.done, at: t0)
        let outcome = tracker.apply([old], at: t0.addingTimeInterval(25 * 60 * 60))
        #expect(outcome.agents.isEmpty)
        #expect(outcome.transitions.isEmpty)
        #expect(outcome.expired == ["demo"])
    }

    @Test func anIdleAgentHasNoDeadline() {
        var tracker = ReportTracker()
        let outcome = tracker.apply([report(.idle, at: t0)], at: t0)
        #expect(outcome.nextDeadline == nil)
    }

    @Test func agentsInOneFolderShareOneProjectAndAgentsWithNoFolderHaveNone() {
        var tracker = ReportTracker()
        let outcome = tracker.apply([
            report(.working, at: t0, key: "a", cwd: "/work/app"),
            report(.idle, at: t0, key: "b", cwd: "/work/app"),
            report(.done, at: t0, key: "c", cwd: nil),
        ], at: t0)
        #expect(outcome.projects.map(\.id.local) == ["/work/app"])
        #expect(outcome.projects.first?.name == "app")
        #expect(outcome.projects.first?.path == "/work/app")
        #expect(outcome.agents.map { $0.projectID?.local } == ["/work/app", "/work/app", nil])
    }

    @Test func aTmuxOrSessionKeyIsNamedByItsKindAndAHandMadeKeyByItself() {
        var tracker = ReportTracker()
        let outcome = tracker.apply([
            report(.idle, at: t0, key: "tmux:/s:%3"),
            report(.idle, at: t0, key: "build-bot"),
        ], at: t0)
        #expect(outcome.agents.map(\.name) == ["build-bot", "claude"])
    }

    @Test func aRepeatedKeyKeepsTheNewerReport() {
        var tracker = ReportTracker()
        let older = report(.working, at: t0, message: "old")
        let newer = report(.blocked, at: t0.addingTimeInterval(5), message: "new")
        let outcome = tracker.apply([newer, older], at: t0.addingTimeInterval(5))
        #expect(outcome.agents.map(\.status) == [.blocked])
        #expect(outcome.agents.first?.message == "new")
    }
}

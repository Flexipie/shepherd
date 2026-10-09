import Testing
@testable import HerdrKit

@Suite struct SubscriptionPlannerTests {
    let panes = SubscriptionSet(paneIDs: ["w1:p1"])

    @Test func startsGlobalOnlyThenUpgradesMakeBeforeBreak() {
        var planner = SubscriptionPlanner()
        #expect(planner.handle(.begin) == [.start(generation: 0, .globalOnly)])
        #expect(planner.handle(.started(generation: 0)) == [.gap, .refresh])
        #expect(planner.handle(.desired(panes)) == [.start(generation: 1, panes)])
        #expect(planner.handle(.started(generation: 1)) == [.close(generation: 0), .refresh])
        #expect(planner.active?.set == panes)
        #expect(planner.handle(.desired(panes)) == [])
    }

    @Test func oneUpgradeAtATimeThenTheLatestSet() {
        var planner = SubscriptionPlanner()
        _ = planner.handle(.begin)
        _ = planner.handle(.started(generation: 0))
        _ = planner.handle(.desired(panes))
        let more = SubscriptionSet(paneIDs: ["w1:p1", "w1:p2"])
        #expect(planner.handle(.desired(more)) == [])
        #expect(planner.handle(.started(generation: 1)) == [.close(generation: 0), .refresh, .start(generation: 2, more)])
    }

    @Test func rejectedUpgradeKeepsTheOldSubscription() {
        var planner = SubscriptionPlanner()
        _ = planner.handle(.begin)
        _ = planner.handle(.started(generation: 0))
        _ = planner.handle(.desired(panes))
        #expect(planner.handle(.startFailed(generation: 1, .server(.paneNotFound, message: ""))) == [.refresh])
        #expect(planner.active?.generation == 0)
        #expect(planner.handle(.desired(panes)) == [.start(generation: 2, panes)])
        _ = planner.handle(.startFailed(generation: 2, .server(.paneNotFound, message: "")))
        _ = planner.handle(.desired(panes))
        #expect(planner.handle(.startFailed(generation: 3, .server(.paneNotFound, message: ""))) == [.scheduleRetry(.milliseconds(500))])
        #expect(planner.handle(.desired(panes)) == [])
        #expect(planner.handle(.retry) == [.start(generation: 4, panes)])
    }

    @Test func endedSubscriptionGoesStaleAndResubscribes() {
        var planner = SubscriptionPlanner()
        _ = planner.handle(.begin)
        _ = planner.handle(.started(generation: 0))
        #expect(planner.handle(.ended(generation: 0, .server(.eventsLost, message: ""))) ==
                [.gap, .state(.stale("fell behind herdr's events")), .start(generation: 1, .globalOnly)])
        #expect(planner.handle(.started(generation: 1)) == [.gap, .refresh])
    }

    @Test func notRunningBacksOff() {
        var planner = SubscriptionPlanner()
        _ = planner.handle(.begin)
        #expect(planner.handle(.startFailed(generation: 0, .notRunning)) ==
                [.state(.disconnected("herdr is not running")), .scheduleRetry(.milliseconds(500))])
        #expect(planner.handle(.retry) == [.start(generation: 1, .globalOnly)])
        #expect(planner.handle(.startFailed(generation: 1, .notRunning)).last == .scheduleRetry(.seconds(1)))
    }

    @Test func staleGenerationsAreIgnoredOrClosed() {
        var planner = SubscriptionPlanner()
        _ = planner.handle(.begin)
        _ = planner.handle(.started(generation: 0))
        #expect(planner.handle(.ended(generation: 7, .disconnected)) == [])
        #expect(planner.handle(.started(generation: 7)) == [.close(generation: 7)])
    }

    @Test func backoffCapsAtAMinute() {
        #expect(Backoff.delay(afterFailures: 1) == .milliseconds(500))
        #expect(Backoff.delay(afterFailures: 50) == .seconds(60))
    }
}

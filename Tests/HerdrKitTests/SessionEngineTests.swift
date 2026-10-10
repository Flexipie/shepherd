import Foundation
import HerdrFake
import Testing
@testable import HerdrKit

@Suite struct SessionEngineTests {
    /// A started fake and engine, torn down by `finish`.
    struct Harness {
        let fake: FakeHerdrServer
        let engine: SessionEngine
        let log: UpdateLog

        static func make(_ herd: FakeHerd = .basic, startFake: Bool = true) async throws -> Harness {
            let fake = FakeHerdrServer(herd: herd)
            if startFake { try await fake.start() }
            let engine = SessionEngine(client: HerdrClient(socketPath: fake.path), debounce: .milliseconds(10),
                                       subscribeTimeout: .seconds(1))
            let log = UpdateLog.recording(engine)
            await engine.start()
            return Harness(fake: fake, engine: engine, log: log)
        }

        /// Live with every agent pane subscribed and nothing else in flight.
        func settled() async throws {
            _ = try await withTimeout { try await log.wait { $0.connection == .live } }
            let paneIDs = await Set(fake.herd.panes.filter { $0.agent != nil }.map(\.id))
            try await withTimeout {
                while await fake.subscribedPaneSets != [paneIDs] { try await Task.sleep(for: .milliseconds(5)) }
            }
        }

        func finish() async {
            await engine.stop()
            await fake.stop()
        }
    }

    @Test func startsLiveAndSubscribesToEveryAgentPane() async throws {
        let h = try await Harness.make()
        try await h.settled()
        // The shell pane is left out: each subscribed pane costs herdr a check every 100 ms.
        #expect(await h.fake.subscribedPaneSets.first?.contains("w1:p2") == false)
        let update = try #require(await h.log.latest)
        #expect(update.session.agents.count == 3)
        #expect(update.session.workingCount == 2)
        #expect(update.compatibility == .matched)
        #expect(await h.fake.subscriberLowWater == 1)
        await h.finish()
    }

    @Test func statusEventRefreshesAndOrdersNeedsYou() async throws {
        let h = try await Harness.make()
        try await h.settled()
        await h.fake.setStatus("w2:p2", "blocked")
        let update = try await withTimeout { try await h.log.wait { $0.status("w2:p2") == .blocked } }
        #expect(update.session.needsYou.map(\.id) == ["w2:p2"])
        #expect(update.transitions.first?.to == .blocked)
        #expect(update.session.agent("w2:p2")?.since?.precision == .exact)
        await h.finish()
    }

    @Test func burstOfEventsCoalesces() async throws {
        let h = try await Harness.make()
        try await h.settled()
        let before = await h.fake.snapshotCount
        for _ in 0..<50 { await h.fake.emit("workspace_updated") }
        await h.fake.setStatus("w1:p1", "done")
        _ = try await withTimeout { try await h.log.wait { $0.status("w1:p1") == .done } }
        try await Task.sleep(for: .milliseconds(100))
        #expect(await h.fake.snapshotCount - before <= 3)
        #expect(await h.fake.maxConcurrentSnapshots == 1)
        await h.finish()
    }

    @Test func eventDuringSlowSnapshotCausesOneMoreRead() async throws {
        let h = try await Harness.make()
        try await h.settled()
        await h.fake.setSnapshotDelay(.milliseconds(150))
        let before = await h.fake.snapshotCount
        await h.fake.setStatus("w1:p1", "blocked")
        try await withTimeout { await h.fake.wait(for: .snapshots(atLeast: before + 1)) }
        await h.fake.setStatus("w2:p2", "done")
        _ = try await withTimeout { try await h.log.wait { $0.status("w1:p1") == .blocked && $0.status("w2:p2") == .done } }
        // The event that arrived mid-read causes exactly one more read, and no further ones.
        try await withTimeout { await h.fake.wait(for: .snapshots(atLeast: before + 2)) }
        try await Task.sleep(for: .milliseconds(250))
        #expect(await h.fake.snapshotCount - before == 2)
        #expect(await h.fake.maxConcurrentSnapshots == 1)
        await h.finish()
    }

    @Test func subscriptionsFollowPanesWithoutAGap() async throws {
        let h = try await Harness.make()
        try await h.settled()
        await h.fake.addPane(FakeHerd.Pane(id: "w1:p3", workspaceID: "w1", status: "working"))
        try await h.settled()
        await h.fake.setStatus("w1:p3", "blocked")
        _ = try await withTimeout { try await h.log.wait { $0.status("w1:p3") == .blocked } }
        await h.fake.removePane("w1:p2")
        try await h.settled()
        #expect(await h.fake.subscriberLowWater == 1)
        await h.finish()
    }

    @Test func aShellPaneThatGainsAnAgentIsSubscribed() async throws {
        let h = try await Harness.make()
        try await h.settled()
        await h.fake.detectAgent("w1:p2", kind: "codex")
        try await h.settled()
        await h.fake.setStatus("w1:p2", "blocked")
        _ = try await withTimeout { try await h.log.wait { $0.status("w1:p2") == .blocked } }
        await h.finish()
    }

    @Test func eventsLostGoesStaleThenRecovers() async throws {
        let h = try await Harness.make()
        try await h.settled()
        let mark = await h.log.updates.count
        await h.fake.update { $0.setStatus("w1:p1", "blocked") }
        await h.fake.sendEventsLost()
        _ = try await withTimeout { try await h.log.wait(after: mark) { $0.connection == .stale("fell behind herdr's events") } }
        let recovered = try await withTimeout { try await h.log.wait(after: mark) { $0.connection == .live && $0.status("w1:p1") == .blocked } }
        // The change happened while events were lost, so its time is only an upper bound.
        #expect(recovered.session.agent("w1:p1")?.since?.precision == .noLaterThan)
        await h.finish()
    }

    @Test func herdrStoppingAndReturning() async throws {
        let h = try await Harness.make()
        try await h.settled()
        let mark = await h.log.updates.count
        await h.fake.stop()
        _ = try await withTimeout { try await h.log.wait(after: mark) { $0.connection == .disconnected("herdr is not running") } }
        try await h.fake.start()
        _ = try await withTimeout { try await h.log.wait(after: mark) { $0.connection == .live } }
        await h.finish()
    }

    @Test func notRunningAtLaunchThenStarted() async throws {
        let h = try await Harness.make(startFake: false)
        _ = try await withTimeout { try await h.log.wait { $0.connection == .disconnected("herdr is not running") } }
        try await h.fake.start()
        try await h.settled()
        await h.finish()
    }

    @Test func newerProtocolStillShowsData() async throws {
        var herd = FakeHerd.basic
        herd.protocolVersion = 23
        let h = try await Harness.make(herd)
        let update = try await withTimeout { try await h.log.wait { $0.connection == .live } }
        #expect(update.compatibility == .newer(23))
        #expect(update.session.agents.count == 3)
        await h.finish()
    }

    @Test func focusingAFinishedAgentClearsIt() async throws {
        let h = try await Harness.make()
        try await h.settled()
        await h.fake.setStatus("w1:p1", "done")
        _ = try await withTimeout { try await h.log.wait { $0.session.needsYou.map(\.id) == ["w1:p1"] } }
        try await HerdrClient(socketPath: h.fake.path).focusAgent(paneID: "w1:p1")
        _ = try await withTimeout { try await h.log.wait { $0.status("w1:p1") == .idle && $0.session.needsYou.isEmpty } }
        await h.finish()
    }

    @Test func stopLeavesNoSubscribers() async throws {
        let h = try await Harness.make()
        try await h.settled()
        await h.engine.stop()
        try await withTimeout { await h.fake.wait(for: .subscribers(0)) }
        await h.fake.stop()
    }
}

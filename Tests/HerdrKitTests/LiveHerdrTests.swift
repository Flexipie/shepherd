import Foundation
import Testing
@testable import HerdrKit

/// Read-only checks against the herdr on this machine. Skipped unless `SHEPHERD_LIVE=1`.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["SHEPHERD_LIVE"] == "1"))
struct LiveHerdrTests {
    @Test func pingAndSnapshot() async throws {
        let client = HerdrClient()
        let pong = try await client.ping()
        #expect(pong.protocol > 0)
        let snapshot = try await client.snapshot()
        #expect(snapshot.protocol == pong.protocol)
        #expect(!snapshot.workspaces.isEmpty)
        #expect(Set(snapshot.agents.map(\.id)).isSubset(of: Set(snapshot.panes.map(\.id))))
    }

    @Test func engineGoesLiveAndSubscribesPerPane() async throws {
        let client = HerdrClient()
        let expected = try await client.snapshot()
        let engine = SessionEngine(client: client)
        let log = UpdateLog.recording(engine)
        await engine.start()
        let live = try await withTimeout { try await log.wait { $0.connection == .live } }
        #expect(live.session.agents.count == expected.agents.count)
        // Give the upgrade to per-pane subscriptions time to be accepted; a rejection would go stale.
        try await Task.sleep(for: .seconds(1))
        #expect(await log.latest?.connection == .live)
        #expect(await engine.planner.active?.set.paneIDs == Set(expected.panes.map(\.id)))
        await engine.stop()
    }
}

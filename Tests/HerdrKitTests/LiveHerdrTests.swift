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
}

import Foundation
import HerdrFake
import Testing
@testable import HerdrKit

@Suite struct HerdrClientTests {
    @Test func pingAndSnapshot() async throws {
        let fake = try await startedFake()
        defer { Task { await fake.stop() } }
        let client = HerdrClient(socketPath: fake.path)

        let pong = try await client.ping()
        #expect(pong.protocol == 22)
        let snapshot = try await client.snapshot()
        #expect(snapshot.panes.count == 4)
        #expect(snapshot.agents.map(\.id) == ["w1:p1", "w2:p1", "w2:p2"])
        #expect(snapshot.agents.first?.status == .working)
        #expect(await fake.requests == ["ping", "session.snapshot"])
    }

    @Test func notRunningWhenNoSocket() async {
        let client = HerdrClient(socketPath: "/tmp/shf-missing-\(UUID().uuidString.prefix(6)).sock")
        await #expect(throws: HerdrError.notRunning) { try await client.ping() }
    }

    @Test func notRunningAfterStop() async throws {
        let fake = try await startedFake()
        await fake.stop()
        await #expect(throws: HerdrError.notRunning) { try await HerdrClient(socketPath: fake.path).ping() }
    }

    @Test func serverErrorsCarryTheirCode() async throws {
        let fake = try await startedFake()
        defer { Task { await fake.stop() } }
        await #expect(throws: HerdrError.server(ServerErrorCode(rawValue: "invalid_request"), message: "unknown method nope")) {
            try await HerdrClient(socketPath: fake.path).call("nope", params: NoParams(), as: IgnoredResult.self, timeout: .seconds(1))
        }
    }

    @Test func stalledSnapshotTimesOut() async throws {
        let fake = try await startedFake()
        defer { Task { await fake.stop() } }
        await fake.setStallSnapshots(true)
        var timeouts = HerdrClient.Timeouts()
        timeouts.snapshot = .milliseconds(200)
        let client = HerdrClient(socketPath: fake.path, timeouts: timeouts)
        await #expect(throws: HerdrError.timeout) { try await withTimeout { try await client.snapshot() } }
    }

    @Test func focusMarksFinishedAgentSeen() async throws {
        let fake = try await startedFake()
        defer { Task { await fake.stop() } }
        await fake.setStatus("w1:p1", "done")
        try await HerdrClient(socketPath: fake.path).focusAgent(paneID: "w1:p1")
        #expect(await fake.focusedTargets == ["w1:p1"])
        #expect(await fake.herd.status(of: "w1:p1") == "idle")
    }

    @Test func largeSnapshotArrivesWhole() async throws {
        var herd = FakeHerd(workspaces: [.init(id: "w1", label: String(repeating: "x", count: 70))])
        herd.panes = (1...400).map { FakeHerd.Pane(id: "w1:p\($0)", workspaceID: "w1") }
        let fake = try await startedFake(herd)
        defer { Task { await fake.stop() } }
        let snapshot = try await HerdrClient(socketPath: fake.path).snapshot()
        #expect(snapshot.agents.count == 400)
    }
}

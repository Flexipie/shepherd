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

    @Test func readReturnsTheVisibleText() async throws {
        let fake = try await startedFake()
        defer { Task { await fake.stop() } }
        await fake.update { $0.setStatus("w2:p1", "blocked") }
        let client = HerdrClient(socketPath: fake.path)
        let text = try await client.readAgent(paneID: "w2:p1", lines: 40)
        #expect(text == FakeScreens.codexApproval)
        let last = try await client.readAgent(paneID: "w2:p1", lines: 1)
        #expect(last == "  Press enter to confirm or esc to cancel")
        await #expect(throws: HerdrError.server(ServerErrorCode(rawValue: "agent_not_found"), message: "nope not found")) {
            try await client.readAgent(paneID: "nope", lines: 1)
        }
    }

    @Test func sendKeysAndInput() async throws {
        let fake = try await startedFake()
        defer { Task { await fake.stop() } }
        let client = HerdrClient(socketPath: fake.path)
        try await client.sendKeys(paneID: "w1:p1", keys: ["1"])
        try await client.sendInput(paneID: "w1:p1", text: "use sqlite", keys: ["enter"])
        #expect(await fake.sentKeys.map(\.keys) == [["1"]])
        #expect(await fake.sentInput.map(\.text) == ["use sqlite"])
        #expect(await fake.sentInput.map(\.keys) == [["enter"]])
        // A shell pane is not an agent, so herdr refuses keys for it.
        await #expect(throws: HerdrError.self) { try await client.sendKeys(paneID: "w1:p2", keys: ["enter"]) }
        await #expect(throws: HerdrError.self) { try await client.sendKeys(paneID: "w1:p1", keys: ["not-a-key"]) }
    }

    @Test func promptRefusesBlockedAgents() async throws {
        let fake = try await startedFake()
        defer { Task { await fake.stop() } }
        let client = HerdrClient(socketPath: fake.path)
        try await client.promptAgent(paneID: "w2:p1", text: "add a test")
        #expect(await fake.sentPrompts.map(\.text) == ["add a test"])
        await fake.setStatus("w2:p1", "blocked")
        await #expect(throws: HerdrError.server(ServerErrorCode(rawValue: "agent_blocked"),
                                                message: "agent w2:p1 is blocked and requires interactive input")) {
            try await client.promptAgent(paneID: "w2:p1", text: "again")
        }
    }

    @Test func worktreeThenAgent() async throws {
        let fake = try await startedFake()
        defer { Task { await fake.stop() } }
        let client = HerdrClient(socketPath: fake.path)
        let created = try await client.createWorktree(workspaceID: "w1", branch: "feature/a")
        #expect(created == HerdrClient.CreatedWorktree(workspaceID: "w3", rootPaneID: "w3:p1", branch: "feature/a"))
        try await client.startAgent(name: "claude-1", kind: "claude", paneID: created.rootPaneID, args: ["--flag"])
        #expect(await fake.startedAgents.map(\.args) == [["--flag"]])
        // The pane runs an agent now, and the name is taken.
        await #expect(throws: HerdrError.self) {
            try await client.startAgent(name: "claude-2", kind: "claude", paneID: created.rootPaneID, args: [])
        }
        let other = try await client.createWorktree(workspaceID: "w1", branch: nil)
        await #expect(throws: HerdrError.self) {
            try await client.startAgent(name: "claude-1", kind: "claude", paneID: other.rootPaneID, args: [])
        }
        await #expect(throws: HerdrError.self) { _ = try await client.createWorktree(workspaceID: "nope", branch: nil) }
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

import Foundation
import HerdrFake
import HerdrKit
import Testing
@testable import HerdrSource
@testable import ShepherdCore

@MainActor
@Suite struct HerdrSourceTests {
    struct TimedOut: Error {}

    /// Feeds a source's updates into a store and waits for a condition on it.
    func until(_ store: HerdStore, _ condition: @MainActor (HerdStore) -> Bool) async throws {
        for _ in 0..<400 {
            if condition(store) { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw TimedOut()
    }

    func running(_ fake: FakeHerdrServer, history: [HerdTransition] = [], log: TransitionLog? = nil) -> (HerdStore, HerdrSource) {
        let source = HerdrSource(client: HerdrClient(socketPath: fake.path), history: history,
                                 debounce: .milliseconds(10), activatesTerminal: false)
        let store = HerdStore(log: log)
        store.add(source)
        store.start()
        return (store, source)
    }

    @Test func adaptsTheHerdrSession() async throws {
        let fake = FakeHerdrServer()
        await fake.update {
            $0.workspaces[1].tokens = ["pr": "12"]
            $0.panes[3].tokens = ["review": "safe"]
        }
        try await fake.start()
        let (store, _) = running(fake)
        try await until(store) { $0.overallState == .live }
        #expect(store.agents.map(\.id.description) == ["herdr:w1:p1", "herdr:w2:p1", "herdr:w2:p2"])
        #expect(store.agents.map(\.kind) == ["claude", "codex", "claude"])
        #expect(store.agents.first?.project == "workspace 1")
        #expect(store.projects.map(\.id.description) == ["herdr:w1", "herdr:w2"])
        #expect(store.projects.map(\.name) == ["workspace 1", "workspace 2"])
        #expect(store.projects.last?.tokens == ["pr": "12"])
        #expect(store.agents.map(\.projectID?.local) == ["w1", "w2", "w2"])
        // Workspace tokens stay on the project; an agent carries only its own.
        #expect(store.agents.last?.tokens == ["review": "safe"])
        #expect(store.agents.first?.tokens == [:])
        #expect(store.workingCount == 2)
        #expect(store.statusLines["herdr"] == ["herdr 0.0.0-fake"])

        await fake.setStatus("w2:p2", "blocked")
        try await until(store) { !$0.needsYou.isEmpty }
        #expect(store.needsYou.first?.status == .blocked)
        #expect(store.lastTransitions.first?.marker == "term-w2:p2|2")
        await store.stop()
        await fake.stop()
    }

    @Test func focusMarksTheAgentSeen() async throws {
        let fake = FakeHerdrServer()
        try await fake.start()
        let (store, _) = running(fake)
        await fake.setStatus("w1:p1", "done")
        try await until(store) { $0.needsYou.count == 1 }
        try await store.focus(AgentID(source: "herdr", local: "w1:p1"))
        try await until(store) { $0.needsYou.isEmpty }
        #expect(await fake.focusedTargets == ["w1:p1"])
        await store.stop()
        await fake.stop()
    }

    @Test func focusProjectSwitchesWorkspace() async throws {
        let fake = FakeHerdrServer()
        try await fake.start()
        let (store, _) = running(fake)
        try await until(store) { $0.overallState == .live }
        #expect(store.projects.allSatisfy { !$0.isFocusedInSource })
        try await store.focusProject(ProjectID(source: "herdr", local: "w2"))
        #expect(await fake.focusedWorkspaces == ["w2"])
        try await until(store) { $0.projects.last?.isFocusedInSource == true }
        await #expect(throws: HerdrError.self) { try await store.focusProject(ProjectID(source: "herdr", local: "nope")) }
        await store.stop()
        await fake.stop()
    }

    @Test func disconnectedWhenHerdrIsMissing() async throws {
        let fake = FakeHerdrServer()
        let (store, _) = running(fake)
        try await until(store) { $0.overallState == .disconnected("herdr is not running") }
        await store.stop()
    }

    @Test func exactTimeSurvivesARestartThroughTheLog() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "shepherd-log-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        let fake = FakeHerdrServer()
        try await fake.start()

        // First run: see the agent block, which logs the transition with its marker.
        let log = TransitionLog(url: url)
        let (first, _) = running(fake, log: log)
        try await until(first) { $0.overallState == .live }
        await fake.setStatus("w1:p1", "blocked")
        try await until(first) { $0.needsYou.first?.since?.precision == .exact }
        let blockedAt = try #require(first.needsYou.first?.since?.date)
        await first.stop()
        for _ in 0..<100 where await log.load().isEmpty { try await Task.sleep(for: .milliseconds(10)) }

        // Second run: nothing changed in herdr, so the logged exact time comes back.
        let (second, _) = running(fake, history: await TransitionLog(url: url).load())
        try await until(second) { !$0.needsYou.isEmpty }
        let restored = try #require(second.needsYou.first?.since)
        #expect(restored.precision == .exact)
        #expect(abs(restored.date.timeIntervalSince(blockedAt)) < 1)
        await second.stop()

        // Third run after the agent moved on: the old time no longer applies.
        await fake.setStatus("w1:p1", "working")
        await fake.setStatus("w1:p1", "blocked")
        let (third, _) = running(fake, history: await TransitionLog(url: url).load())
        try await until(third) { !$0.needsYou.isEmpty }
        #expect(third.needsYou.first?.since?.precision == .noLaterThan)
        await third.stop()
        await fake.stop()
    }

    @Test func seedsComeFromTheLatestHerdrEntryOnly() {
        let pane = AgentID(source: "herdr", local: "w1:p1")
        let history = [
            HerdTransition(agent: pane, from: .working, to: .blocked, at: Date(timeIntervalSince1970: 1), marker: "t1|3"),
            HerdTransition(agent: pane, from: .blocked, to: .working, at: Date(timeIntervalSince1970: 2), marker: "t1|4"),
            HerdTransition(agent: AgentID(source: "other", local: "w1:p1"), from: nil, to: .done, at: Date(), marker: "x|9"),
            HerdTransition(agent: AgentID(source: "herdr", local: "gone"), from: .done, to: nil, at: Date(), marker: "t2|1"),
        ]
        let seeds = HerdrSource.seeds(from: history)
        #expect(seeds.map(\.paneID) == ["w1:p1"])
        #expect(seeds.first?.stateChangeSeq == 4)
        #expect(seeds.first?.terminalID == "t1")
    }
}

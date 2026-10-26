import DemoHerd
import Foundation
import ShepherdCore
import Testing

@MainActor
/// Serialized: every demo uses the same socket and spool.
@Suite(.serialized) struct DemoHerdTests {
    /// Waits up to 5 s for `condition`, so a busy test run does not fail on timing.
    func until(_ condition: () -> Bool) async {
        for _ in 0..<500 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
    }

    @Test func everySourceComesUpLiveWithItsAgents() async throws {
        let demo = try await DemoHerd.start()
        defer { demo.removeFiles() }
        let store = HerdStore()
        demo.sources.forEach(store.add)
        store.start()
        await until { store.agents.count == 8 && store.overallState == .live }

        #expect(store.overallState == .live)
        let bySource = Dictionary(grouping: store.agents, by: \.id.source).mapValues(\.count)
        #expect(bySource == ["herdr": 4, "report": 2, "tmux": 2])
        #expect(store.agents.filter(\.isInferred).map(\.id.source) == ["tmux", "tmux"])
        #expect(store.needsYou.map(\.status) == [.blocked, .blocked, .blocked, .done])
        await store.stop()
    }

    @Test func answeringTheScreenAgentSetsItWorking() async throws {
        let demo = try await DemoHerd.start()
        defer { demo.removeFiles() }
        let store = HerdStore()
        demo.sources.forEach(store.add)
        store.start()
        await until { store.agents.contains { $0.isInferred && $0.status == .blocked } }
        let waiting = try #require(store.agents.first { $0.isInferred && $0.status == .blocked })

        #expect(try await store.read(waiting.id, lines: 20).contains("Do you want to proceed?"))
        try await store.sendKeys(waiting.id, ["1"])
        await until { store.agents.first { $0.id == waiting.id }?.status == .working }
        #expect(store.agents.first { $0.id == waiting.id }?.status == .working)
        await store.stop()
    }
}

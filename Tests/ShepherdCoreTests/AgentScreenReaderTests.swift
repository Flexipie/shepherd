import Foundation
import Testing
@testable import ShepherdCore

/// Actions whose reads are counted and answer with the agent's screen, or wait while `held`.
@MainActor
final class ReadingActions: AgentActions {
    var reads: [AgentID] = []
    var capabilities: SourceCapabilities = [.readOutput]
    var held = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func release() {
        held = false
        waiting.forEach { $0.resume() }
        waiting = []
    }

    func read(_ agent: AgentID, lines: Int) async throws -> String {
        reads.append(agent)
        if held { await withCheckedContinuation { waiting.append($0) } }
        return "screen of \(agent.local)\n\n"
    }

    func jump(to agent: AgentID) {}
    func focusProject(_ project: ProjectID) {}
    func capabilities(of agent: AgentID) -> SourceCapabilities { capabilities }
    func sendKeys(_ agent: AgentID, _ keys: [String]) async throws {}
    func sendText(_ agent: AgentID, _ text: String) async throws {}
    func prompt(_ agent: AgentID, _ text: String) async throws {}
    func startTask(_ task: NewTask) async throws -> AgentID { AgentID(source: "herdr", local: "new") }
}

@MainActor
@Suite struct AgentScreenReaderTests {
    let store = HerdStore()
    let actions = ReadingActions()

    init() {
        store.add(StubSource("herdr"))
    }

    func reader(debounce: Duration = .milliseconds(20)) -> AgentScreenReader {
        AgentScreenReader(store: store, actions: actions, lineCount: 40, debounce: debounce)
    }

    func id(_ local: String) -> AgentID { AgentID(source: "herdr", local: local) }

    func show(_ agents: [HerdAgent]) {
        store.apply(SourceUpdate(agents: agents, state: .live), from: "herdr")
    }

    /// Waits up to 3 s for `condition`, so a busy test run does not fail on timing.
    func until(_ condition: () -> Bool) async {
        for _ in 0..<300 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
    }

    func settle() async {
        try? await Task.sleep(for: .milliseconds(100))
    }

    @Test func movingThroughAgentsReadsOnlyWhereItStops() async {
        let reader = reader()
        reader.show(id("a"))
        reader.show(id("b"))
        reader.show(id("c"))
        await until { reader.lines != nil }
        await settle()
        #expect(actions.reads == [id("c")])
        #expect(reader.lines == ["screen of c"])
    }

    @Test func closingBeforeTheDebounceReadsNothing() async {
        let reader = reader()
        reader.show(id("a"))
        reader.close()
        await settle()
        #expect(actions.reads.isEmpty)
        #expect(reader.agent == nil)
    }

    @Test func aReadArrivingAfterCloseIsDroppedAndNothingMoreIsRead() async {
        show([herdAgent("herdr", "a", .working)])
        let reader = reader()
        actions.held = true
        reader.show(id("a"))
        await until { actions.reads.count == 1 }
        reader.close()
        actions.release()
        show([herdAgent("herdr", "a", .blocked)])
        await settle()
        #expect(reader.text == nil)
        #expect(actions.reads == [id("a")])
    }
}

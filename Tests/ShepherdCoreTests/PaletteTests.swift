import Foundation
import Testing
@testable import ShepherdCore
@testable import ShepherdModules

@MainActor
@Suite struct PaletteTests {
    let store = HerdStore()
    let herdr = StubSource("herdr")
    let other = StubSource("other")
    let context: ModuleContext

    let early = Date(timeIntervalSince1970: 100)
    let late = Date(timeIntervalSince1970: 200)

    init() {
        herdr.capabilities = [.focus, .focusProject]
        other.capabilities = [.focus]
        store.add(herdr)
        store.add(other)
        context = ModuleContext(store: store, presence: Presence(), actions: RecordingActions())
    }

    func items() -> [PaletteItem] {
        PaletteIndex.items(context: context, modules: [QueueModule(context: context)])
    }

    func ids(_ results: [PaletteResult]) -> [String] {
        results.map(\.id)
    }

    func showHerd() {
        store.apply(SourceUpdate(
            agents: [herdAgent("herdr", "a", .working, project: "api", projectID: "w1"),
                     herdAgent("herdr", "b", .done, since: early, project: "web", projectID: "w2", tokens: ["summary": "tests pass"]),
                     herdAgent("herdr", "c", .blocked, since: late, project: "api", projectID: "w1")],
            projects: [herdProject("herdr", "w1", name: "api", tokens: ["pr": "#142 draft"]), herdProject("herdr", "w2", name: "web")],
            state: .live), from: "herdr")
    }

    @Test func emptyQueryIsNeedsYouThenAgentsThenProjectsThenCommands() {
        showHerd()
        let results = PaletteSearch.results(items(), query: "")
        #expect(ids(results) == ["agent/herdr:c", "agent/herdr:b", "agent/herdr:a",
                                 "project/herdr:w1", "project/herdr:w2", "command/queue.next"])
        #expect(results.allSatisfy { $0.highlights.isEmpty })
        #expect(results.first?.item.action == .jump(AgentID(source: "herdr", local: "c")))
        #expect(results[3].item.action == .focusProject(ProjectID(source: "herdr", local: "w1")))
        #expect(results.last?.item.action == .nextInQueue)
        if case .project(_, let count, _) = results[3].item.kind { #expect(count == 2) } else { Issue.record("not a project") }
    }

    @Test func aTokenValueFindsItsAgentAndItsProject() {
        showHerd()
        // The project's PR number is on the project and, through it, on its agents.
        let results = PaletteSearch.results(items(), query: "142")
        #expect(Set(ids(results)) == ["project/herdr:w1", "agent/herdr:a", "agent/herdr:c"])
        // Matches outside the title are found but not highlighted.
        #expect(results.allSatisfy { $0.highlights.isEmpty })
        #expect(ids(PaletteSearch.results(items(), query: "tests pass")) == ["agent/herdr:b"])
    }

    @Test func titlesRankFirstAndHighlight() throws {
        showHerd()
        let results = PaletteSearch.results(items(), query: "web")
        #expect(results.first?.id == "project/herdr:w2")
        let first = try #require(results.first)
        #expect(first.highlights.map { String(first.item.title[$0]) } == ["web"])
        // The project's agent is found by its project's name, below the project.
        #expect(ids(results).contains("agent/herdr:b"))
    }

    @Test func needsYouBreaksTies() {
        showHerd()
        // All three agents are named "agent x" and score the same on "agent".
        let agents = ids(PaletteSearch.results(items(), query: "agent")).filter { $0.hasPrefix("agent/") }
        #expect(agents == ["agent/herdr:c", "agent/herdr:b", "agent/herdr:a"])
    }

    @Test func everyWordMustMatch() {
        showHerd()
        #expect(ids(PaletteSearch.results(items(), query: "api needs")) == ["agent/herdr:c"])
        #expect(PaletteSearch.results(items(), query: "api zzz").isEmpty)
    }

    @Test func resultsAreCapped() {
        let agents = (1...80).map { herdAgent("herdr", "a\($0)", .idle) }
        store.apply(SourceUpdate(agents: agents, state: .live), from: "herdr")
        #expect(PaletteSearch.results(items(), query: "").count == PaletteSearch.limit)
        #expect(PaletteSearch.results(items(), query: "agent").count == PaletteSearch.limit)
        #expect(PaletteSearch.results(items(), query: "agent", limit: 5).count == 5)
    }

    @Test func agentsAndProjectsOfSourcesThatAreNotLiveAreLeftOut() {
        showHerd()
        store.apply(SourceUpdate(agents: [herdAgent("other", "x", .blocked, since: early)],
                                 projects: [herdProject("other", "o1")], state: .stale("fell behind")), from: "other")
        let all = ids(PaletteSearch.results(items(), query: ""))
        #expect(!all.contains("agent/other:x"))
        #expect(!all.contains("project/other:o1"))
        // With no live agent waiting, the queue offers no "next".
        store.apply(SourceUpdate(agents: [], state: .live), from: "herdr")
        #expect(ids(PaletteSearch.results(items(), query: "")).isEmpty)
    }

    @Test func actionsFollowCapabilities() {
        other.capabilities = []
        store.apply(SourceUpdate(agents: [herdAgent("other", "x", .idle, projectID: "o1")], projects: [herdProject("other", "o1")],
                                 state: .live), from: "other")
        let results = PaletteSearch.results(items(), query: "")
        #expect(ids(results) == ["agent/other:x", "project/other:o1"])
        #expect(results.allSatisfy { $0.item.action == nil })
    }

    @Test func contextSizesAndTokensComeWithTheRow() {
        store.apply(SourceUpdate(agents: [herdAgent("herdr", "a", .idle, tokens: ["summary": "hi"])], state: .live), from: "herdr")
        context.agentContext.set(1234, for: AgentID(source: "herdr", local: "a"))
        guard case .agent(let row)? = items().first?.kind else {
            Issue.record("no agent")
            return
        }
        #expect(row.contextTokens == 1234)
        #expect(row.tokens == [[StyledToken(name: "summary", text: "hi")]])
    }
}

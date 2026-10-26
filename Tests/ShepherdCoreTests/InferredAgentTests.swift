import Foundation
import Testing
@testable import ShepherdCore

/// Screen readings (inferred agents) next to reports of the same pane: what the store shows and what it announces.
@MainActor
@Suite struct InferredAgentTests {
    static let pane = "tmux:/tmp/tmux-501/default:%3"
    let folder = "/work/app"

    func screenAgent(status: HerdStatus = .working) -> HerdAgent {
        HerdAgent(id: AgentID(source: "tmux", local: Self.pane), kind: "claude", name: "claude",
                  projectID: ProjectID(source: "tmux", local: folder), project: "app", status: status, isInferred: true)
    }

    func reportAgent(status: HerdStatus = .blocked) -> HerdAgent {
        HerdAgent(id: AgentID(source: "report", local: Self.pane), kind: "claude", name: "claude",
                  projectID: ProjectID(source: "report", local: folder), project: "app", status: status)
    }

    func screenProject() -> HerdProject {
        HerdProject(id: ProjectID(source: "tmux", local: folder), name: "app", path: folder, isInferred: true)
    }

    func reportProject() -> HerdProject {
        HerdProject(id: ProjectID(source: "report", local: folder), name: "app", path: folder)
    }

    func makeStore() -> HerdStore {
        let store = HerdStore()
        store.add(StubSource("tmux"))
        store.add(StubSource("report"))
        return store
    }

    @Test func aScreenReadingIsHiddenWhereAReportHasTheSamePane() {
        let store = makeStore()
        store.apply(SourceUpdate(agents: [screenAgent()], projects: [screenProject()], state: .live), from: "tmux")
        store.apply(SourceUpdate(agents: [reportAgent()], projects: [reportProject()], state: .live), from: "report")
        #expect(store.agents.map(\.id) == [AgentID(source: "report", local: Self.pane)])
        #expect(store.projects.map(\.id) == [ProjectID(source: "report", local: folder)])
        #expect(store.needsYou.map(\.id) == [AgentID(source: "report", local: Self.pane)])
    }

    @Test func aScreenReadingAloneIsShown() {
        let store = makeStore()
        store.apply(SourceUpdate(agents: [screenAgent(status: .blocked)], projects: [screenProject()], state: .live), from: "tmux")
        #expect(store.agents.map(\.status) == [.blocked])
        #expect(store.agents.first?.isInferred == true)
        #expect(store.projects.map(\.isInferred) == [true])
    }

    @Test func aScreenFolderStaysWhileAnotherScreenAgentUsesIt() {
        let store = makeStore()
        let second = HerdAgent(id: AgentID(source: "tmux", local: "tmux:/tmp/tmux-501/default:%4"), kind: "codex",
                               name: "codex", projectID: ProjectID(source: "tmux", local: folder), project: "app",
                               status: .idle, isInferred: true)
        store.apply(SourceUpdate(agents: [screenAgent(), second], projects: [screenProject()], state: .live), from: "tmux")
        store.apply(SourceUpdate(agents: [reportAgent()], projects: [reportProject()], state: .live), from: "report")
        // The screen row for the reported pane goes; the report keeps that pane, and the other screen row
        // still uses the folder, so its card stays alongside the report's.
        #expect(store.agents.map(\.id) == [second.id, AgentID(source: "report", local: Self.pane)])
        #expect(store.projects.map(\.id.source) == ["tmux", "report"])
    }

    @Test func aScreenReadingIsNotAnnouncedButAReportIs() async {
        let store = makeStore()
        var events = store.events().makeAsyncIterator()
        let screen = HerdTransition(agent: screenAgent().id, from: .working, to: .blocked, at: Date())
        let report = HerdTransition(agent: reportAgent().id, from: .working, to: .blocked, at: Date())
        store.apply(SourceUpdate(agents: [screenAgent(status: .blocked)], state: .live, transitions: [screen]), from: "tmux")
        store.apply(SourceUpdate(agents: [reportAgent()], state: .live, transitions: [report]), from: "report")
        // Events are buffered in order, so the first one is all the screen reading could have produced.
        guard case .transitions(let announced)? = await events.next() else {
            Issue.record("no transitions were announced")
            return
        }
        #expect(announced == [report])
    }
}

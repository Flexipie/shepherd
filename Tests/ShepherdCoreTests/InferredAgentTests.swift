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
        let tmux = StubSource("tmux")
        tmux.capabilities = [.focus, .readOutput, .sendKeys, .sendText, .prompt, .startAgent, .createWorktree]
        store.add(tmux)
        let report = StubSource("report")
        report.capabilities = []
        store.add(report)
        return store
    }

    // A hooked Claude Code in a tmux pane is one row: the pane's, so it can be read, answered and
    // jumped to, with the report's state (#84).
    @Test func aReportOfAScreenAgentShowsAsTheScreenRowWithTheReportsState() {
        let store = makeStore()
        store.apply(SourceUpdate(agents: [screenAgent()], projects: [screenProject()], state: .live), from: "tmux")
        let reported = HerdAgent(id: AgentID(source: "report", local: Self.pane), kind: "claude", name: "claude",
                                 projectID: ProjectID(source: "report", local: folder), project: "app", status: .blocked,
                                 since: Since(Date(timeIntervalSince1970: 100), .exact), message: "Ran the tests",
                                 question: "Run make app?")
        store.apply(SourceUpdate(agents: [reported], projects: [reportProject()], state: .live), from: "report")
        let tmuxID = AgentID(source: "tmux", local: Self.pane)
        #expect(store.agents.map(\.id) == [tmuxID])
        let row = store.agents[0]
        #expect(row.status == .blocked)
        #expect(row.isInferred == false)
        #expect(row.since == Since(Date(timeIntervalSince1970: 100), .exact))
        #expect(row.message == "Ran the tests")
        #expect(row.question == "Run make app?")
        #expect(store.capabilities(of: row.id).contains(.sendText))
        #expect(store.needsYou.map(\.id) == [tmuxID])
        // The pane's checkout stays, so new tasks can start there; the report's folder adds nothing.
        #expect(store.projects.map(\.id) == [ProjectID(source: "tmux", local: folder)])
        #expect(store.canStartTask(in: ProjectID(source: "tmux", local: folder)))
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
        // The reported pane and the other screen agent share the checkout: two rows, one project.
        #expect(store.agents.map(\.id) == [AgentID(source: "tmux", local: Self.pane), second.id])
        #expect(store.projects.map(\.id.source) == ["tmux"])
    }

    @Test func aMergedRowsChangesAreToldOnceUnderItsRow() async {
        let store = makeStore()
        var events = store.events().makeAsyncIterator()
        let tmuxID = AgentID(source: "tmux", local: Self.pane)
        let screen = HerdTransition(agent: screenAgent().id, from: .working, to: .blocked, at: Date())
        let appeared = HerdTransition(agent: reportAgent().id, from: nil, to: .working, at: Date())
        let report = HerdTransition(agent: reportAgent().id, from: .working, to: .blocked, at: Date())
        store.apply(SourceUpdate(agents: [screenAgent()], state: .live), from: "tmux")
        store.apply(SourceUpdate(agents: [reportAgent(status: .working)], state: .live, transitions: [appeared]), from: "report")
        #expect(store.lastTransitions.isEmpty)
        store.apply(SourceUpdate(agents: [screenAgent(status: .blocked)], state: .live, transitions: [screen]), from: "tmux")
        #expect(store.lastTransitions.isEmpty)
        store.apply(SourceUpdate(agents: [reportAgent()], state: .live, transitions: [report]), from: "report")
        let told = HerdTransition(agent: tmuxID, from: .working, to: .blocked, at: report.at)
        #expect(store.lastTransitions == [told])
        // Events are buffered in order, so the first one is the first anything announced.
        guard case .transitions(let announced)? = await events.next() else {
            Issue.record("no transitions were announced")
            return
        }
        #expect(announced == [told])
        // The report going away is not the row leaving: the pane is still there.
        let closed = HerdTransition(agent: reportAgent().id, from: .blocked, to: nil, at: Date())
        store.apply(SourceUpdate(agents: [], state: .live, transitions: [closed]), from: "report")
        #expect(store.agents.map(\.id) == [tmuxID])
        #expect(store.agents.first?.isInferred == true)
    }

    // A hooked Claude Code in herdr is herdr's one row: herdr's state, the report's words where herdr has none.
    @Test func aReportOfAHerdrAgentBySessionIsOneRow() {
        let store = HerdStore()
        let herdr = StubSource("herdr")
        herdr.capabilities = [.focus, .readOutput, .sendKeys, .sendText]
        store.add(herdr)
        let reports = StubSource("report")
        reports.capabilities = []
        store.add(reports)
        let session = AgentSession(kind: "claude", id: "abc-123", cwd: folder)
        let herdrAgent = HerdAgent(id: AgentID(source: "herdr", local: "w1:p1"), kind: "claude", name: "claude",
                                   projectID: ProjectID(source: "herdr", local: "w1"), project: "app",
                                   status: .working, session: session)
        let reported = HerdAgent(id: AgentID(source: "report", local: "session:abc-123"), kind: "claude", name: "claude",
                                 projectID: ProjectID(source: "report", local: folder), project: "app", status: .blocked,
                                 session: session, message: "Ran the tests")
        store.apply(SourceUpdate(agents: [herdrAgent], projects: [herdProject("herdr", "w1")], state: .live), from: "herdr")
        store.apply(SourceUpdate(agents: [reported], projects: [reportProject()], state: .live,
                                 transitions: [HerdTransition(agent: reported.id, from: .working, to: .blocked, at: Date())]),
                    from: "report")
        #expect(store.agents.map(\.id) == [herdrAgent.id])
        #expect(store.agents.first?.status == .working)
        #expect(store.agents.first?.message == "Ran the tests")
        #expect(store.projects.map(\.id) == [ProjectID(source: "herdr", local: "w1")])
        #expect(store.lastTransitions.isEmpty)
    }
}

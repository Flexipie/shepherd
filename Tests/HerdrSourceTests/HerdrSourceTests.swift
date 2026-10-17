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

    func running(_ fake: FakeHerdrServer, history: [HerdTransition] = [], log: TransitionLog? = nil,
                 config: URL? = nil) -> (HerdStore, HerdrSource) {
        let source = HerdrSource(client: HerdrClient(socketPath: fake.path), history: history,
                                 debounce: .milliseconds(10), activatesTerminal: false, configURL: config)
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
            $0.panes[0].cwd = "/tmp/project-1"
            $0.panes[0].sessionID = "session-1"
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
        #expect(store.agents.first?.session == AgentSession(kind: "claude", id: "session-1", cwd: "/tmp/project-1"))
        #expect(store.agents.last?.session == nil)
        #expect(store.workingCount == 2)
        #expect(store.statusLines["herdr"] == ["herdr 0.0.0-fake"])

        await fake.setStatus("w2:p2", "blocked")
        try await until(store) { !$0.needsYou.isEmpty }
        #expect(store.needsYou.first?.status == .blocked)
        // herdr's counter is shared by all agents: the basic herd is at 3, so this change is 4.
        #expect(store.lastTransitions.first?.marker == "term-w2:p2|4")
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

    @Test func answeringABlockedAgent() async throws {
        let fake = FakeHerdrServer()
        try await fake.start()
        let (store, _) = running(fake)
        await fake.setStatus("w1:p1", "blocked")
        try await until(store) { $0.needsYou.count == 1 }
        let agent = AgentID(source: "herdr", local: "w1:p1")
        #expect(store.capabilities(of: agent).isSuperset(of: [.readOutput, .sendKeys, .sendText]))
        let text = try await store.read(agent, lines: 30)
        #expect(ChoiceParser.choices(in: text).map(\.key) == ["1", "2", "3"])
        try await store.sendKeys(agent, ["1"])
        try await until(store) { $0.needsYou.isEmpty }
        await fake.setStatus("w1:p1", "blocked")
        try await until(store) { $0.needsYou.count == 1 }
        try await store.sendText(agent, "use the second one")
        try await until(store) { $0.needsYou.isEmpty }
        #expect(await fake.sentKeys.map(\.keys) == [["1"]])
        #expect(await fake.sentInput.map(\.keys) == [["enter"]])
        await store.stop()
        await fake.stop()
    }

    @Test func promptingAnIdleAgent() async throws {
        let fake = FakeHerdrServer()
        try await fake.start()
        let (store, _) = running(fake)
        try await until(store) { $0.overallState == .live }
        let agent = AgentID(source: "herdr", local: "w2:p1")
        try await store.prompt(agent, "write the docs")
        try await until(store) { $0.agents.first { $0.id == agent }?.status == .working }
        await fake.setStatus("w2:p1", "blocked")
        try await until(store) { $0.needsYou.count == 1 }
        await #expect(throws: AgentSourceError.failed("herdr: agent w2:p1 is blocked and requires interactive input")) {
            try await store.prompt(agent, "again")
        }
        await store.stop()
        await fake.stop()
    }

    @Test func startingATask() async throws {
        let fake = FakeHerdrServer()
        try await fake.start()
        let (store, _) = running(fake)
        try await until(store) { $0.overallState == .live }
        let task = NewTask(project: ProjectID(source: "herdr", local: "w1"), branch: "feature/a", kind: "codex", prompt: "add a test")
        #expect(store.canStartTask(in: task.project))
        let agent = try await store.startTask(task, args: ["--full-auto"])
        #expect(agent == AgentID(source: "herdr", local: "w3:p1"))
        try await until(store) { $0.agents.contains { $0.id == agent && $0.kind == "codex" } }
        #expect(await fake.createdWorktrees.map(\.branch) == ["feature/a"])
        #expect(await fake.startedAgents.first?.args == ["--full-auto"])
        #expect(await fake.sentPrompts.map(\.text) == ["add a test"])
        // A failed start says what was left behind.
        let bad = NewTask(project: task.project, branch: "feature/b", kind: "nope", prompt: "")
        await #expect(throws: AgentSourceError.failed("Created worktree feature/b, but nope did not start: herdr: unsupported agent kind nope")) {
            _ = try await store.startTask(bad, args: [])
        }
        await store.stop()
        await fake.stop()
    }

    @Test func workspacesCarryTheirRepo() async throws {
        let fake = FakeHerdrServer()
        await fake.serve(try RecordedFixture.named("basic"))
        try await fake.start()
        let (store, _) = running(fake)
        try await until(store) { $0.overallState == .live && !$0.projects.isEmpty }
        let repos = Dictionary(uniqueKeysWithValues: store.projects.map { ($0.id.local, $0.repo) })
        // w1 is the main checkout; w5 and w6 are linked worktrees of the same repo.
        #expect(repos["w1"] == HerdRepo(key: "repo_key-1", name: "repo_name-1"))
        #expect(repos["w5"] == HerdRepo(key: "repo_key-1", name: "repo_name-1", isLinkedCheckout: true))
        #expect(repos["w6"] == HerdRepo(key: "repo_key-1", name: "repo_name-1", isLinkedCheckout: true))
        // Outside git, no repo.
        #expect(repos["w2"] == .some(nil))
        await store.stop()
        await fake.stop()
    }

    @Test func aNewTaskIsALinkedWorktreeOfItsRepo() async throws {
        let fake = FakeHerdrServer()
        try await fake.start()
        await fake.setRepo("w1", name: "repo-1")
        let (store, _) = running(fake)
        try await until(store) { $0.projects.first?.repo != nil }
        let task = NewTask(project: ProjectID(source: "herdr", local: "w1"), branch: "feature/a", kind: "claude", prompt: "go")
        _ = try await store.startTask(task, args: [])
        try await until(store) { $0.projects.count == 3 }
        #expect(store.projects.map(\.repo) == [HerdRepo(key: "/tmp/repo-1/.git", name: "repo-1"), nil,
                                               HerdRepo(key: "/tmp/repo-1/.git", name: "repo-1", isLinkedCheckout: true)])
        await store.stop()
        await fake.stop()
    }

    @Test func onlyASessionIDBecomesASession() {
        let id = Agent(id: "p1", workspaceID: "w1", agent: "claude", status: .idle, cwd: "/tmp/project-1",
                       session: Agent.Session(agent: "claude", kind: "id", value: "session-1"))
        #expect(HerdrSource.session(id) == AgentSession(kind: "claude", id: "session-1", cwd: "/tmp/project-1"))
        let path = Agent(id: "p1", workspaceID: "w1", agent: "claude", status: .idle,
                         session: Agent.Session(agent: "claude", kind: "path", value: "/tmp/x"))
        #expect(HerdrSource.session(path) == nil)
        let unnamed = Agent(id: "p1", workspaceID: "w1", agent: "codex", status: .idle,
                            session: Agent.Session(kind: "id", value: "session-2"))
        #expect(HerdrSource.session(unnamed)?.kind == "codex")
    }

    @Test func agentNamesFollowHerdrsRules() {
        let name = HerdrSource.agentName(kind: "claude")
        #expect(name.hasPrefix("claude-"))
        #expect(name.count <= 32)
        #expect(name.allSatisfy { ($0.isASCII && ($0.isLowercase || $0.isNumber)) || $0 == "-" })
        #expect(HerdrSource.agentName(kind: "1Weird Kind!").hasPrefix("agent-"))
    }

    @Test func sidebarLayoutFollowsHerdrsConfig() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "shepherd-herdr-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let config = directory.appending(path: "config.toml")
        try Data("[ui.sidebar.spaces]\nrows = [[\"workspace\", \"$pr\"]]\n".utf8).write(to: config)

        let fake = FakeHerdrServer()
        try await fake.start()
        let (store, _) = running(fake, config: config)
        try await until(store) { $0.overallState == .live }
        #expect(store.tokenLayouts["herdr"] == TokenLayout(projects: [[TokenEntry(name: "pr")]]))

        try Data("[ui.sidebar.spaces]\nrows = [[{ token = \"$pr\", fg = \"nope\" }]]\n".utf8).write(to: config, options: .atomic)
        try await until(store) { $0.tokenLayouts["herdr"] == nil }
        #expect(store.statusLines["herdr"] == ["herdr 0.0.0-fake",
                                               "herdr config line 2: ui.sidebar.spaces.rows[0][0].fg: must be #RGB or #RRGGBB"])

        try Data("[ui.sidebar.agents]\nrows = [[\"$summary\"]]\n".utf8).write(to: config, options: .atomic)
        try await until(store) { $0.tokenLayouts["herdr"] == TokenLayout(agents: [[TokenEntry(name: "summary")]]) }
        #expect(store.statusLines["herdr"] == ["herdr 0.0.0-fake"])
        // A config change re-sends the herd it has.
        #expect(store.agents.count == 3)
        await store.stop()
        await fake.stop()
    }

    @Test func tokenAndLabelChangesArrive() async throws {
        let fake = FakeHerdrServer()
        try await fake.start()
        let (store, _) = running(fake)
        try await until(store) { $0.overallState == .live }
        await fake.setToken("w1", "pr", "#9")
        try await until(store) { $0.projects.first?.tokens == ["pr": "#9"] }
        await fake.setToken("w2:p1", "summary", "done soon")
        try await until(store) { $0.agents.first { $0.id.local == "w2:p1" }?.tokens == ["summary": "done soon"] }
        await fake.setToken("w1", "pr", "")
        try await until(store) { $0.projects.first?.tokens == [:] }
        await fake.setWorkspace("w3", label: "docs")
        try await until(store) { $0.projects.map(\.name) == ["workspace 1", "workspace 2", "docs"] }
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

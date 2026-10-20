import Foundation
import Testing
@testable import ShepherdCore

@Suite struct PluginEventRuleTests {
    func read(_ json: String) throws -> (manifest: PluginManifest, problems: [String]) {
        try PluginManifest.read(Data(json.utf8), at: "plugins/x/shepherd-plugin.json")
    }

    @Test func readsRulesAndSkipsTheOnesThatCannotRun() throws {
        let (manifest, problems) = try read(#"""
        {"id": "p", "events": [
            {"on": ["agent.finished", "agent.blocked"], "command": ["./badge.sh"]},
            {"on": ["agent.nope"], "command": ["x"]},
            {"on": ["task.started", "later"], "command": ["./tag.sh"]},
            {"on": ["agent.started"]},
            "x"]}
        """#)
        #expect(manifest.events == [
            PluginEventRule(on: [.agentFinished, .agentBlocked], command: ["./badge.sh"]),
            PluginEventRule(on: [.taskStarted], command: ["./tag.sh"]),
        ])
        let known = "agent.started, agent.blocked, agent.finished, task.started"
        #expect(problems == [
            "p.events[1].on has names that are not events (known: \(known))",
            "p.events[2].on has names that are not events (known: \(known))",
            #"p.events[3] needs "on" (a list of event names) and a command (a list of strings)"#,
            #"p.events[4] needs "on" (a list of event names) and a command (a list of strings)"#,
        ])
    }

    @Test func eventsMustBeAList() throws {
        let (manifest, problems) = try read(#"{"id": "p", "events": {"on": ["agent.finished"]}}"#)
        #expect(manifest.events.isEmpty)
        #expect(problems == ["p.events must be a list"])
    }
}

@Suite struct PluginEventMappingTests {
    let agent = AgentID(source: "herdr", local: "w1:p1")
    let project = ProjectID(source: "herdr", local: "w1")

    func raised(_ from: HerdStatus?, _ to: HerdStatus?) -> [PluginEvent] {
        PluginEventOccurrence.raised(by: .transitions([HerdTransition(agent: agent, from: from, to: to, at: Date())])).map(\.event)
    }

    @Test func transitionsRaiseTheMatchingEvents() {
        #expect(raised(nil, .working) == [.agentStarted])
        #expect(raised(.working, .blocked) == [.agentBlocked])
        #expect(raised(.working, .done) == [.agentFinished])
        #expect(raised(.done, .working) == [])
        #expect(raised(.working, nil) == [])
        #expect(raised(nil, nil) == [])
    }

    @Test func aFinishedAgentIsItsOwnTarget() {
        let occurrences = PluginEventOccurrence.raised(by: .transitions([HerdTransition(agent: agent, from: .working, to: .done, at: Date())]))
        #expect(occurrences == [PluginEventOccurrence(event: .agentFinished, agent: agent, target: .agent(agent))])
    }

    @Test func aStartedTaskTargetsItsProject() {
        #expect(PluginEventOccurrence.raised(by: .taskStarted(agent, project))
                == [PluginEventOccurrence(event: .taskStarted, agent: agent, target: .project(project))])
    }
}

@MainActor
@Suite struct HerdEventStreamTests {
    let agent = AgentID(source: "herdr", local: "w1:p1")

    @Test func everySubscriberGetsEveryEventInOrder() async {
        let store = HerdStore()
        let first = store.events()
        let second = store.events()
        let working = HerdTransition(agent: agent, from: nil, to: .working, at: Date())
        let done = HerdTransition(agent: agent, from: .working, to: .done, at: Date())
        store.apply(SourceUpdate(agents: [], state: .live, transitions: [working]), from: "herdr")
        store.apply(SourceUpdate(agents: [], state: .live, transitions: [done]), from: "herdr")
        var one = first.makeAsyncIterator()
        #expect(await one.next() == HerdEvent.transitions([working]))
        #expect(await one.next() == HerdEvent.transitions([done]))
        var two = second.makeAsyncIterator()
        #expect(await two.next() == HerdEvent.transitions([working]))
    }

    @Test func aTaskStartIsPublished() async throws {
        let store = HerdStore()
        let source = StubSource("herdr")
        source.capabilities = [.createWorktree, .startAgent]
        source.newAgent = AgentID(source: "herdr", local: "w2:p1")
        store.add(source)
        let stream = store.events()
        let task = NewTask(project: ProjectID(source: "herdr", local: "w1"), kind: "claude", prompt: "hi")
        let started = try await store.startTask(task, args: [])
        var iterator = stream.makeAsyncIterator()
        #expect(await iterator.next() == HerdEvent.taskStarted(started, task.project))
    }
}

/// Plugin events end to end: the host runs the listed plugins with the agent's environment.
@MainActor
@Suite struct PluginEventTests {
    let directory: URL
    let store = HerdStore()
    let source = StubSource("herdr")
    let runner = StubPluginRunner()
    let config = ConfigStore(fixed: .defaults)
    let host: PluginHost
    let agent = AgentID(source: "herdr", local: "w1:p1")

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "shepherd-events-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        source.capabilities = [.focus, .createWorktree, .startAgent]
        source.newAgent = AgentID(source: "herdr", local: "w2:p1")
        store.add(source)
        store.apply(SourceUpdate(
            agents: [HerdAgent(id: agent, kind: "claude", name: "claude", projectID: ProjectID(source: "herdr", local: "w1"),
                               project: "api", status: .working, session: nil)],
            projects: [HerdProject(id: ProjectID(source: "herdr", local: "w1"), name: "api", path: "/tmp/project-1")],
            state: .live), from: "herdr")
        host = PluginHost(directory: directory, runner: runner, store: store, config: config)
    }

    func write(_ folder: String, _ json: String) throws {
        let url = directory.appending(path: folder)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try json.write(to: url.appending(path: PluginManifest.fileName), atomically: true, encoding: .utf8)
    }

    func transition(_ from: HerdStatus?, _ to: HerdStatus?) -> HerdEvent {
        .transitions([HerdTransition(agent: agent, from: from, to: to, at: Date())])
    }

    /// Lets the event runs the host started run to the end; the stub runner does not suspend.
    func settle() async {
        for _ in 0..<100 { await Task.yield() }
    }

    @Test func onlyThePluginsListingTheEventRun() async throws {
        try write("a", #"{"id": "alpha", "events": [{"on": ["agent.finished"], "command": ["./done.sh"]}]}"#)
        try write("b", #"{"id": "beta", "events": [{"on": ["agent.blocked"], "command": ["./blocked.sh"]}]}"#)
        await host.refresh()
        host.handle(transition(.working, .done))
        await settle()
        #expect(runner.runs.map(\.command) == [["./done.sh"]])
        let env = runner.runs[0].environment
        #expect(env["SHEPHERD_EVENT"] == "agent.finished")
        #expect(env["SHEPHERD_AGENT_ID"] == "herdr:w1:p1")
        #expect(env["SHEPHERD_AGENT_NAME"] == "claude")
        #expect(env["SHEPHERD_PROJECT_PATH"] == "/tmp/project-1")
        #expect(env["SHEPHERD_PLUGIN_ROOT"] == host.plugins.first { $0.id == "alpha" }?.folder.path)
    }

    @Test func aDisabledPluginDoesNotRun() async throws {
        try write("a", #"{"id": "alpha", "events": [{"on": ["agent.finished"], "command": ["./done.sh"]}]}"#)
        let disabled = PluginHost(directory: directory, runner: runner, store: store,
                                  config: ConfigStore(fixed: ShepherdConfig(disabledPlugins: ["alpha"])))
        await disabled.refresh()
        disabled.handle(transition(.working, .done))
        await settle()
        #expect(runner.runs.isEmpty)
    }

    @Test func aRepeatInsideTheWindowIsDropped() async throws {
        try write("a", #"{"id": "alpha", "events": [{"on": ["agent.blocked"], "command": ["./blocked.sh"]}]}"#)
        await host.refresh()
        let start = ContinuousClock.now
        host.handle(transition(.working, .blocked), at: start)
        host.handle(transition(.working, .blocked), at: start + .seconds(2))
        await settle()
        #expect(runner.runs.count == 1)
        host.handle(transition(.working, .blocked), at: start + .seconds(6))
        await settle()
        #expect(runner.runs.count == 2)
    }

    @Test func aFailingCommandIsReportedInTheFooter() async throws {
        try write("a", #"{"id": "alpha", "events": [{"on": ["agent.finished"], "command": ["./done.sh"]}]}"#)
        runner.results["./done.sh"] = PluginRunResult(status: 1, stdout: "", stderr: "no token")
        await host.refresh()
        host.handle(transition(.working, .done))
        await settle()
        #expect(config.problems == ["agent.finished: exited with 1: no token"])
    }

    @Test func storeTransitionsReachTheRunningHost() async throws {
        try write("a", #"{"id": "alpha", "events": [{"on": ["agent.finished"], "command": ["./done.sh"]}]}"#)
        await host.refresh()
        host.startEvents()
        defer { host.stopEvents() }
        store.apply(SourceUpdate(agents: [], state: .live, transitions: [HerdTransition(agent: agent, from: .working, to: .done, at: Date())]),
                    from: "herdr")
        await settle()
        #expect(runner.runs.map(\.command) == [["./done.sh"]])
    }

    @Test func aStartedTaskRunsTaskStartedInItsProject() async throws {
        try write("a", #"{"id": "alpha", "events": [{"on": ["task.started"], "command": ["./tag.sh"]}]}"#)
        await host.refresh()
        host.startEvents()
        defer { host.stopEvents() }
        let task = NewTask(project: ProjectID(source: "herdr", local: "w1"), kind: "claude", prompt: "hi")
        _ = try await store.startTask(task, args: [])
        await settle()
        #expect(runner.runs.map(\.command) == [["./tag.sh"]])
        let env = runner.runs[0].environment
        #expect(env["SHEPHERD_EVENT"] == "task.started")
        #expect(env["SHEPHERD_AGENT_ID"] == "herdr:w2:p1")
        #expect(env["SHEPHERD_PROJECT_NAME"] == "api")
    }
}

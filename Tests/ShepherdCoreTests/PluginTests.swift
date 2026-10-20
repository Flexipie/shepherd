import Foundation
import Testing
@testable import ShepherdCore
@testable import ShepherdModules

@Suite struct PluginManifestTests {
    func read(_ json: String) throws -> (manifest: PluginManifest, problems: [String]) {
        try PluginManifest.read(Data(json.utf8), at: "plugins/x/shepherd-plugin.json")
    }

    @Test func readsActionsAndIgnoresUnknownKeys() throws {
        let (manifest, problems) = try read(#"""
        {"id": "badges", "name": "Badges", "events": [{"on": ["agent.finished"], "command": ["./badge.sh"]}],
         "actions": [{"id": "open-pr", "title": "Open PR", "context": "project", "command": ["./open.sh", "--web"],
                      "symbol": "arrow.up.right.square", "later": true},
                     {"id": "refresh", "title": "Refresh", "command": ["./refresh.sh"]}],
         "listActions": ["./list.sh"]}
        """#)
        #expect(problems.isEmpty)
        #expect(manifest.name == "Badges")
        #expect(manifest.actions == [
            PluginAction(id: "open-pr", title: "Open PR", context: .project, command: ["./open.sh", "--web"], symbol: "arrow.up.right.square"),
            PluginAction(id: "refresh", title: "Refresh", command: ["./refresh.sh"]),
        ])
        #expect(manifest.listActions == ["./list.sh"])
    }

    @Test func aBadActionIsSkippedAndTheRestLoad() throws {
        let (manifest, problems) = try read(#"""
        {"id": "p", "actions": [{"id": "a", "title": "A", "command": ["a"]}, {"id": "b", "title": "B"},
                                {"id": "c", "title": "C", "command": ["c"], "context": "window"},
                                {"id": "a", "title": "Again", "command": ["a"]}, "d"],
         "listActions": "nope"}
        """#)
        #expect(manifest.name == "p")
        #expect(manifest.actions.map(\.id) == ["a"])
        #expect(problems == [
            "p.actions[1] needs an id, a title and a command (a list of strings)",
            "p.actions[2].context must be \"global\", \"project\" or \"agent\"",
            "p.actions[3]: id \"a\" is used twice",
            "p.actions[4] must be an object",
            "plugin p: listActions must be a list of strings",
        ])
    }

    @Test func noUsableIDIsNoPlugin() {
        #expect(throws: ConfigProblem("plugins/x/shepherd-plugin.json is not a JSON object")) { try read("[]") }
        #expect(throws: ConfigProblem(#"plugins/x/shepherd-plugin.json: id must be letters, digits, "-", "_" or ".""#)) {
            try read(#"{"id": "has space"}"#)
        }
    }

    @Test func outputIsTextOrJSON() {
        #expect(PluginOutput.parse("  done\n") == PluginOutput(text: "done"))
        #expect(PluginOutput.parse("\n") == PluginOutput())
        #expect(PluginOutput.parse("{not json") == PluginOutput(text: "{not json"))
        let json = PluginOutput.parse(##"{"text": "set", "tokens": {"pr": "#12", "old": "", "gone": null, "files": 4, "x": [1]}}"##)
        #expect(json.text == "set")
        let expected: [String: String?] = ["pr": "#12", "old": nil, "gone": nil, "files": "4"]
        #expect(json.tokens == expected)
    }
}

/// Answers plugin commands from a table, and records what ran.
final class StubPluginRunner: PluginRunner, @unchecked Sendable {
    var results: [String: PluginRunResult] = [:]
    private(set) var runs: [(command: [String], environment: [String: String])] = []

    func run(_ command: [String], in folder: URL, environment: [String: String], timeout: Duration) async throws -> PluginRunResult {
        runs.append((command, environment))
        return results[command.joined(separator: " ")] ?? PluginRunResult(status: 0, stdout: "")
    }
}

@MainActor
@Suite struct PluginHostTests {
    let directory: URL
    let store = HerdStore()
    let runner = StubPluginRunner()
    let config = ConfigStore(fixed: .defaults)
    let host: PluginHost

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "shepherd-plugins-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let herdr = StubSource("herdr")
        herdr.capabilities = [.focus, .focusProject]
        store.add(herdr)
        store.apply(SourceUpdate(
            agents: [HerdAgent(id: AgentID(source: "herdr", local: "w1:p1"), kind: "claude", name: "claude",
                               projectID: ProjectID(source: "herdr", local: "w1"), project: "api", status: .done,
                               tokens: ["pr": "#1"], session: AgentSession(kind: "claude", id: "session-1", cwd: "/tmp/project-1"))],
            projects: [HerdProject(id: ProjectID(source: "herdr", local: "w1"), name: "api", path: "/tmp/project-1")],
            state: .live), from: "herdr")
        host = PluginHost(directory: directory, runner: runner, store: store, config: config)
    }

    func write(_ folder: String, _ json: String) throws {
        let url = directory.appending(path: folder)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try json.write(to: url.appending(path: PluginManifest.fileName), atomically: true, encoding: .utf8)
    }

    @Test func loadsEachFolderAndReportsProblems() async throws {
        try write("b", #"{"id": "beta", "actions": [{"id": "x", "title": "X", "command": ["x"], "context": "agent"}]}"#)
        try write("a", #"{"id": "alpha", "actions": [{"id": "y", "title": "Y", "command": ["y"]}, {"id": "bad"}]}"#)
        try write("c", #"{"id": "alpha"}"#)
        try write("d", "not json")
        try FileManager.default.createDirectory(at: directory.appending(path: "e"), withIntermediateDirectories: true)
        await host.refresh()
        #expect(host.plugins.map(\.id) == ["alpha", "beta"])
        #expect(host.actions(for: .global).map(\.action.id) == ["y"])
        #expect(host.actions(for: .agent).map(\.action.id) == ["x"])
        #expect(config.problems == ["alpha.actions[1] needs an id, a title and a command (a list of strings); "
                                    + "plugin alpha is in two folders; using the first; plugins/d/shepherd-plugin.json is not a JSON object"])
    }

    @Test func aDisabledPluginIsSkipped() async throws {
        try write("a", #"{"id": "alpha", "actions": [{"id": "y", "title": "Y", "command": ["y"]}]}"#)
        let config = ConfigStore(fixed: ShepherdConfig(disabledPlugins: ["alpha"]))
        let host = PluginHost(directory: directory, runner: runner, store: store, config: config)
        await host.refresh()
        #expect(host.plugins.isEmpty)
    }

    @Test func listedActionsJoinTheManifestsOwn() async throws {
        try write("a", #"{"id": "alpha", "actions": [{"id": "y", "title": "Y", "command": ["y"]}], "listActions": ["./list"]}"#)
        runner.results["./list"] = PluginRunResult(status: 0, stdout: #"""
        {"actions": [{"id": "z", "title": "Z", "command": ["z"], "context": "project"},
                     {"id": "y", "title": "Shadowed", "command": ["other"]}]}
        """#)
        await host.refresh()
        #expect(host.actions(for: .global).map(\.action.title) == ["Y"])
        #expect(host.actions(for: .project).map(\.action.id) == ["z"])
        runner.results["./list"] = PluginRunResult(status: 1, stdout: "", stderr: "herdr is not running")
        await host.refresh()
        // A failed listing keeps the last good actions and says why.
        #expect(host.actions(for: .project).map(\.action.id) == ["z"])
        #expect(config.problems == ["plugin alpha: exited with 1: herdr is not running"])
    }

    @Test func runningAnActionPassesItsTargetAndAppliesTokens() async throws {
        try write("a", #"{"id": "alpha", "actions": [{"id": "pr", "title": "PR", "command": ["./pr"], "context": "agent"}]}"#)
        await host.refresh()
        runner.results["./pr"] = PluginRunResult(status: 0, stdout: ##"{"text": "opened", "tokens": {"pr": "#12 draft", "ci": "green"}}"##)
        let agent = AgentID(source: "herdr", local: "w1:p1")
        let text = try await host.run(PluginActionRef(plugin: "alpha", action: "pr", target: .agent(agent)))
        #expect(text == "opened")
        let env = try #require(runner.runs.last?.environment)
        #expect(env["SHEPHERD_AGENT_ID"] == "herdr:w1:p1")
        #expect(env["SHEPHERD_AGENT_KIND"] == "claude")
        #expect(env["SHEPHERD_SESSION_ID"] == "session-1")
        #expect(env["SHEPHERD_CWD"] == "/tmp/project-1")
        #expect(env["SHEPHERD_PROJECT_ID"] == "herdr:w1")
        #expect(env["SHEPHERD_PROJECT_PATH"] == "/tmp/project-1")
        #expect(env["SHEPHERD_TOKENS"] == ##"{"pr":"#1"}"##)
        #expect(env["SHEPHERD_PLUGIN_ROOT"] == directory.appending(path: "a").resolvingSymlinksInPath().path)
        // Plugin tokens go over the source's, on rows too.
        let context = ModuleContext(store: store, presence: Presence(), actions: RecordingActions(), plugins: host)
        let row = try #require(context.tokens(of: store.agents[0]))
        #expect(row == ["pr": "#12 draft", "ci": "green"])
        // An empty value removes a token.
        runner.results["./pr"] = PluginRunResult(status: 0, stdout: #"{"tokens": {"ci": ""}}"#)
        #expect(try await host.run(PluginActionRef(plugin: "alpha", action: "pr", target: .agent(agent))) == nil)
        #expect(host.tokenValues(for: .agent(agent)) == ["pr": "#12 draft"])
    }

    @Test func aFailureSaysWhy() async throws {
        try write("a", #"{"id": "alpha", "actions": [{"id": "y", "title": "Deploy", "command": ["./deploy"]}]}"#)
        await host.refresh()
        runner.results["./deploy"] = PluginRunResult(status: 2, stdout: "", stderr: "first\nno credentials\n")
        await #expect(throws: ConfigProblem("Exited with 2: no credentials")) {
            try await host.run(PluginActionRef(plugin: "alpha", action: "y", target: .global))
        }
        await #expect(throws: ConfigProblem("That action is gone; its plugin changed")) {
            try await host.run(PluginActionRef(plugin: "alpha", action: "nope", target: .global))
        }
    }

    @Test func globalActionsArePaletteCommands() async throws {
        try write("a", #"""
        {"id": "alpha", "name": "Alpha", "actions": [{"id": "y", "title": "Deploy", "command": ["./deploy"], "symbol": "paperplane"},
                                                     {"id": "z", "title": "Agent only", "command": ["z"], "context": "agent"}]}
        """#)
        await host.refresh()
        let context = ModuleContext(store: store, presence: Presence(), actions: RecordingActions(), plugins: host)
        let commands = PluginsModule(context: context).commands
        #expect(commands == [PaletteCommand(id: "plugins.alpha.y", title: "Deploy", symbol: "paperplane", keywords: ["Alpha", "plugin"],
                                            action: .plugin(PluginActionRef(plugin: "alpha", action: "y", target: .global)))])
        #expect(PluginsModule(context: ModuleContext(store: store, presence: Presence(), actions: RecordingActions())).commands.isEmpty)
    }
}

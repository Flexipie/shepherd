import Foundation
import Testing
@testable import ShepherdCore
@testable import ShepherdModules

@Suite struct PluginGadgetParseTests {
    func read(_ json: String) throws -> (manifest: PluginManifest, problems: [String]) {
        try PluginManifest.read(Data(json.utf8), at: "plugins/x/shepherd-plugin.json")
    }

    @Test func aGadgetIsReadLeniently() throws {
        let (manifest, problems) = try read(#"{"id": "load", "gadget": {"title": "Load", "command": ["./load.sh"], "every": 30, "later": 1}}"#)
        #expect(problems.isEmpty)
        #expect(manifest.gadget == PluginGadget(title: "Load", command: ["./load.sh"], every: 30))
        // Missing title and every take defaults; a tiny interval is raised.
        #expect(try read(#"{"id": "a", "gadget": {"command": ["x"]}}"#).manifest.gadget == PluginGadget(command: ["x"], every: 60))
        #expect(try read(#"{"id": "a", "gadget": {"command": ["x"], "every": 0.1}}"#).manifest.gadget?.every == 2)
        #expect(try read(#"{"id": "a", "gadget": {"command": ["x"], "every": 1e21}}"#).manifest.gadget?.every == 86_400)
    }

    @Test func aBadGadgetIsAProblemAndThePluginStillLoads() throws {
        let (manifest, problems) = try read(#"{"id": "p", "actions": [{"id": "a", "title": "A", "command": ["a"]}], "gadget": {"every": 5}}"#)
        #expect(manifest.gadget == nil)
        #expect(manifest.actions.map(\.id) == ["a"])
        #expect(problems == ["p.gadget needs a command (a list of strings)"])
        let (kept, everyProblem) = try read(#"{"id": "p", "gadget": {"command": ["x"], "every": "often"}}"#)
        #expect(kept.gadget == PluginGadget(command: ["x"]))
        #expect(everyProblem == ["p.gadget.every must be a number of seconds"])
    }

    @Test func outputIsACard() throws {
        let card = try PluginGadget.card(from: #"""
        {"title": "Load", "detail": "8 cores", "lines": ["up 3 days", 4],
         "meters": [{"label": "1 min", "fraction": 0.25, "text": "2.0"}, {"label": "5 min", "fraction": 1.4}],
         "later": true}
        """#, id: "load", title: "Fallback")
        #expect(card == GadgetCard(id: "load", title: "Load", detail: "8 cores", meters: [
            GadgetMeter(id: "0", label: "1 min", fraction: 0.25, valueText: "2.0"),
            GadgetMeter(id: "1", label: "5 min", fraction: 1, valueText: "100%"),
        ], lines: ["up 3 days"]))
        #expect(try PluginGadget.card(from: "{}", id: "a", title: "Fallback") == GadgetCard(id: "a", title: "Fallback"))
        #expect(throws: ConfigProblem("must print a JSON object with a title, meters and lines")) {
            try PluginGadget.card(from: "load 2.0", id: "a", title: "A")
        }
        #expect(throws: ConfigProblem("meters[0] needs a label and a fraction (a number from 0 to 1)")) {
            try PluginGadget.card(from: #"{"meters": [{"label": "CPU", "fraction": "0.3"}]}"#, id: "a", title: "A")
        }
    }
}

@MainActor
@Suite struct PluginGadgetRunTests {
    let directory: URL
    let store = HerdStore()
    let runner = StubPluginRunner()
    let config = ConfigStore(fixed: .defaults)
    let presence = Presence()
    let host: PluginHost

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "shepherd-gadgets-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        host = PluginHost(directory: directory, runner: runner, store: store, config: config)
    }

    func write(_ folder: String, _ json: String) throws {
        let url = directory.appending(path: folder)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try json.write(to: url.appending(path: PluginManifest.fileName), atomically: true, encoding: .utf8)
    }

    /// Waits up to 3 s for `condition`, so a busy test run does not fail on timing.
    func until(_ condition: () -> Bool) async {
        for _ in 0..<300 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
    }

    func module() -> PluginsModule {
        PluginsModule(context: ModuleContext(store: store, presence: presence, actions: RecordingActions(), plugins: host))
    }

    @Test func aRunSetsTheCardAndAFailureSaysWhyOnItAndInTheFooter() async throws {
        try write("a", #"{"id": "load", "name": "Load", "gadget": {"command": ["./load"]}}"#)
        await host.load()
        let plugin = try #require(host.gadgetPlugins.first)
        runner.results["./load"] = PluginRunResult(status: 0, stdout: #"{"lines": ["ok"]}"#)
        await host.runGadget(plugin)?.value
        #expect(host.gadgetCard(for: plugin) == GadgetCard(id: "load", title: "Load", lines: ["ok"]))
        #expect(runner.runs.last?.environment["SHEPHERD_PLUGIN_ROOT"] == plugin.folder.path)

        runner.results["./load"] = PluginRunResult(status: 1, stdout: "", stderr: "no sensor\n")
        await host.runGadget(plugin)?.value
        #expect(host.gadgetCard(for: plugin) == GadgetCard(id: "load", title: "Load", lines: ["ok", "Exited with 1: no sensor"], isStale: true))
        #expect(config.problems == ["plugin load: gadget exited with 1: no sensor"])

        runner.results["./load"] = PluginRunResult(status: 0, stdout: #"{"lines": ["back"]}"#)
        await host.runGadget(plugin)?.value
        #expect(host.gadgetCard(for: plugin)?.lines == ["back"])
        #expect(config.problems.isEmpty)
    }

    @Test func aRunStillGoingIsNotStartedAgain() async throws {
        try write("a", #"{"id": "load", "gadget": {"command": ["./load"]}}"#)
        await host.load()
        let plugin = try #require(host.gadgetPlugins.first)
        let first = host.runGadget(plugin)
        #expect(host.runGadget(plugin) == nil)
        await first?.value
        #expect(runner.runs.count == 1)
    }

    @Test func withNoGadgetPluginThereIsNoSectionAndNoCommand() async throws {
        try write("a", #"{"id": "acts", "actions": [{"id": "y", "title": "Deploy", "command": ["./deploy"]}]}"#)
        await host.load()
        let module = module()
        #expect(module.panel == nil)
        #expect(!module.commands.contains { $0.action == .gadgets })

        try write("b", #"{"id": "load", "gadget": {"command": ["./load"]}}"#)
        await host.load()
        #expect(module.panel?.tab == .gadgets)
        #expect(module.commands.contains { $0.action == .gadgets })
    }

    @Test func gadgetsRunOnlyWhileTheTabShows() async throws {
        try write("a", #"{"id": "load", "gadget": {"command": ["./load"]}}"#)
        runner.results["./load"] = PluginRunResult(status: 0, stdout: #"{"title": "Load"}"#)
        await host.load()
        let module = module()
        presence.setPanel("notch", showing: .agents)
        try await Task.sleep(for: .milliseconds(80))
        #expect(runner.runs.isEmpty)
        #expect(module.loops.isEmpty)

        presence.setPanel("notch", showing: .gadgets)
        await until { module.panel?.items.count == 1 }
        #expect(runner.runs.count == 1)
        #expect(module.panel?.items == [.gadget(GadgetCard(id: "load", title: "Load"))])

        presence.setPanel("notch", showing: nil)
        await until { module.loops.isEmpty }
        #expect(module.loops.isEmpty)
    }
}

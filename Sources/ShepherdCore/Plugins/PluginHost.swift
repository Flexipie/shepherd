import Foundation
import Observation

/// The user's plugins: loads them from their folder, runs their actions and keeps the tokens they
/// set. Plugins are read when a surface asks (the palette opening), not watched, so nothing runs
/// at idle. Problems go to the config footer under `plugins`.
@MainActor
@Observable
public final class PluginHost {
    public private(set) var plugins: [Plugin] = []
    /// Actions each plugin's `listActions` printed on the last refresh.
    public private(set) var listed: [String: [PluginAction]] = [:]
    /// Tokens plugins set, by target, then by plugin.
    private(set) var tokens: [PluginTarget: [String: [String: String]]] = [:]

    public let directory: URL
    @ObservationIgnored private let runner: any PluginRunner
    @ObservationIgnored private let store: HerdStore
    @ObservationIgnored private let config: ConfigStore
    @ObservationIgnored private var loadProblems: [String] = []
    @ObservationIgnored private var listProblems: [String: String] = [:]
    @ObservationIgnored private var refreshing: Task<Void, Never>?

    public static let actionTimeout: Duration = .seconds(30)
    public static let listTimeout: Duration = .seconds(10)

    public init(directory: URL = PluginHost.defaultDirectory(), runner: any PluginRunner, store: HerdStore, config: ConfigStore) {
        self.directory = directory
        self.runner = runner
        self.store = store
        self.config = config
    }

    /// `SHEPHERD_PLUGINS_PATH`, else `~/.config/shepherd/plugins`.
    public nonisolated static func defaultDirectory(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let path = environment["SHEPHERD_PLUGINS_PATH"], !path.isEmpty { return URL(fileURLWithPath: path) }
        return FileManager.default.homeDirectoryForCurrentUser.appending(path: ".config/shepherd/plugins")
    }

    // MARK: Loading

    /// Reads every plugin's manifest again and runs each `listActions`. A refresh already on its
    /// way is awaited instead of starting another.
    public func refresh() async {
        if let refreshing { return await refreshing.value }
        let task = Task { @MainActor in
            await self.load()
            await self.listAll()
        }
        refreshing = task
        await task.value
        refreshing = nil
    }

    func load() async {
        let directory = directory
        let (loaded, problems) = await Task.detached { Self.read(directory) }.value
        let disabled = Set(config.config.disabledPlugins)
        let enabled = loaded.filter { !disabled.contains($0.id) }
        if plugins != enabled { plugins = enabled }
        let ids = Set(enabled.map(\.id))
        listed = listed.filter { ids.contains($0.key) }
        tokens = tokens.compactMapValues { byPlugin in
            let kept = byPlugin.filter { ids.contains($0.key) }
            return kept.isEmpty ? nil : kept
        }
        loadProblems = problems
        report()
    }

    /// Each folder's manifest, by folder name. A missing directory is no plugins.
    nonisolated static func read(_ directory: URL) -> ([Plugin], [String]) {
        let folders = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil,
                                                                    options: [.skipsHiddenFiles])) ?? []
        var plugins: [Plugin] = []
        var problems: [String] = []
        for folder in folders.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let folder = folder.resolvingSymlinksInPath()
            let file = folder.appending(path: PluginManifest.fileName)
            guard let data = try? Data(contentsOf: file) else { continue }
            do {
                let (manifest, found) = try PluginManifest.read(data, at: "plugins/\(folder.lastPathComponent)/\(PluginManifest.fileName)")
                if plugins.contains(where: { $0.id == manifest.id }) {
                    problems.append("plugin \(manifest.id) is in two folders; using the first")
                    continue
                }
                plugins.append(Plugin(manifest: manifest, folder: folder))
                problems += found
            } catch {
                problems.append(error.message)
            }
        }
        return (plugins, problems)
    }

    private func listAll() async {
        await withTaskGroup(of: (String, [PluginAction]?, String?).self) { group in
            for plugin in plugins {
                guard let command = plugin.manifest.listActions else { continue }
                let runner = runner
                group.addTask {
                    do {
                        let result = try await runner.run(command, in: plugin.folder, environment: ["SHEPHERD_PLUGIN_ROOT": plugin.folder.path],
                                                          timeout: Self.listTimeout)
                        guard result.status == 0 else { return (plugin.id, nil, Self.failure(result)) }
                        var problems: [String] = []
                        let value = try? JSONDecoder().decode(ConfigValue.self, from: Data(result.stdout.utf8))
                        guard case .table(let table)? = value else { return (plugin.id, nil, "listActions must print {\"actions\": [...]}") }
                        let actions = PluginAction.list(table["actions"], at: "\(plugin.id) listActions", problems: &problems)
                        return (plugin.id, actions, problems.first)
                    } catch {
                        return (plugin.id, nil, "\(error)")
                    }
                }
            }
            for await (id, actions, problem) in group {
                listed[id] = actions ?? listed[id]
                listProblems[id] = problem.map { "plugin \(id): \($0)" }
            }
        }
        listProblems = listProblems.filter { id, _ in plugins.contains { $0.id == id } }
        report()
    }

    private func report() {
        let all = loadProblems + listProblems.keys.sorted().compactMap { listProblems[$0] }
        config.report(all.isEmpty ? nil : all.joined(separator: "; "), for: "plugins")
    }

    // MARK: Actions

    /// Every action for `context`, with its plugin, manifest actions first.
    public func actions(for context: PluginAction.Context) -> [(plugin: Plugin, action: PluginAction)] {
        plugins.flatMap { plugin in
            var seen = Set(plugin.manifest.actions.map(\.id))
            let extra = (listed[plugin.id] ?? []).filter { seen.insert($0.id).inserted }
            return (plugin.manifest.actions + extra).filter { $0.context == context }.map { (plugin, $0) }
        }
    }

    public func action(_ ref: PluginActionRef) -> (plugin: Plugin, action: PluginAction)? {
        guard let plugin = plugins.first(where: { $0.id == ref.plugin }) else { return nil }
        let action = plugin.manifest.actions.first { $0.id == ref.action } ?? listed[plugin.id]?.first { $0.id == ref.action }
        return action.map { (plugin, $0) }
    }

    /// Runs an action on its target, applies any tokens it printed, and returns its text.
    /// Throws a message for the user when it cannot run, fails or times out; the caller shows it
    /// under the action's title.
    public func run(_ ref: PluginActionRef) async throws(ConfigProblem) -> String? {
        guard let (plugin, action) = action(ref) else { throw ConfigProblem("That action is gone; its plugin changed") }
        var environment = ref.target.environment(store: store, tokens: allTokens(for: ref.target))
        environment["SHEPHERD_PLUGIN_ROOT"] = plugin.folder.path
        let result: PluginRunResult
        do {
            result = try await runner.run(action.command, in: plugin.folder, environment: environment, timeout: Self.actionTimeout)
        } catch {
            throw ConfigProblem("\(error)")
        }
        guard result.status == 0 else { throw ConfigProblem(Self.failure(result).capitalizedFirst) }
        let output = PluginOutput.parse(result.stdout)
        if !output.tokens.isEmpty, ref.target != .global { apply(output.tokens, from: plugin.id, to: ref.target) }
        return output.text
    }

    /// "exited with 2: no credentials", from the exit status and the last line on stderr.
    nonisolated static func failure(_ result: PluginRunResult) -> String {
        let line = result.stderr.split(whereSeparator: \.isNewline).last.map(String.init)
        return line.map { "exited with \(result.status): \($0)" } ?? "exited with \(result.status)"
    }

    // MARK: Tokens

    func apply(_ changes: [String: String?], from plugin: String, to target: PluginTarget) {
        var mine = tokens[target]?[plugin] ?? [:]
        for (key, value) in changes { mine[key] = value }
        var byPlugin = tokens[target] ?? [:]
        byPlugin[plugin] = mine.isEmpty ? nil : mine
        tokens[target] = byPlugin.isEmpty ? nil : byPlugin
    }

    /// The target's own tokens with the plugins' over them: what its row shows.
    func allTokens(for target: PluginTarget) -> [String: String] {
        let own: [String: String] = switch target {
        case .global: [:]
        case .agent(let id): store.agents.first { $0.id == id }?.tokens ?? [:]
        case .project(let id): store.projects.first { $0.id == id }?.tokens ?? [:]
        }
        return own.merging(tokenValues(for: target)) { _, plugin in plugin }
    }

    /// The tokens plugins set on a target, merged in plugin order.
    public func tokenValues(for target: PluginTarget) -> [String: String] {
        guard let byPlugin = tokens[target] else { return [:] }
        return byPlugin.keys.sorted().reduce(into: [:]) { merged, plugin in
            merged.merge(byPlugin[plugin] ?? [:]) { _, new in new }
        }
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

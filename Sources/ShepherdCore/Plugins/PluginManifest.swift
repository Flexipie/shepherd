import Foundation

/// A plugin's `shepherd-plugin.json`. Read leniently: unknown keys are ignored (later versions
/// add checks and gadgets), and an action or event rule that cannot be used is skipped with a
/// problem while the rest load.
public struct PluginManifest: Sendable, Equatable {
    public static let fileName = "shepherd-plugin.json"

    public let id: String
    public let name: String
    public let actions: [PluginAction]
    /// Prints more actions as JSON (`{"actions": [...]}`), for actions not known in advance.
    public let listActions: [String]?
    /// Commands run when the listed events happen.
    public let events: [PluginEventRule]

    public init(id: String, name: String, actions: [PluginAction] = [], listActions: [String]? = nil,
                events: [PluginEventRule] = []) {
        self.id = id
        self.name = name
        self.actions = actions
        self.listActions = listActions
        self.events = events
    }

    /// Reads a manifest. Throws when there is no usable id; smaller problems are in the result.
    public static func read(_ data: Data, at path: String) throws(ConfigProblem) -> (manifest: PluginManifest, problems: [String]) {
        guard case .table(let table)? = try? JSONDecoder().decode(ConfigValue.self, from: data) else {
            throw ConfigProblem("\(path) is not a JSON object")
        }
        guard case .string(let id)? = table["id"], PluginAction.isValidID(id) else {
            throw ConfigProblem("\(path): id must be letters, digits, \"-\", \"_\" or \".\"")
        }
        let name = if case .string(let name)? = table["name"], !name.isEmpty { name } else { id }
        var problems: [String] = []
        let actions = PluginAction.list(table["actions"], at: "\(id).actions", problems: &problems)
        var listActions: [String]?
        if let value = table["listActions"] {
            listActions = PluginAction.command(value)
            if listActions == nil { problems.append("plugin \(id): listActions must be a list of strings") }
        }
        let events = PluginEventRule.list(table["events"], at: "\(id).events", problems: &problems)
        return (PluginManifest(id: id, name: name, actions: actions, listActions: listActions, events: events), problems)
    }
}

/// A command a plugin offers, for the whole app or for one project or agent.
public struct PluginAction: Sendable, Equatable, Identifiable {
    public enum Context: String, Sendable, Equatable, CaseIterable {
        case global, project, agent
    }

    /// Unique within its plugin.
    public let id: String
    public let title: String
    public let context: Context
    /// The program and its arguments, run from the plugin's folder.
    public let command: [String]
    /// An SF Symbol name.
    public let symbol: String?

    public init(id: String, title: String, context: Context = .global, command: [String], symbol: String? = nil) {
        self.id = id
        self.title = title
        self.context = context
        self.command = command
        self.symbol = symbol
    }

    static func isValidID(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 64 && id.allSatisfy { ($0.isASCII && ($0.isLetter || $0.isNumber)) || "-_.".contains($0) }
    }

    static func command(_ value: ConfigValue) -> [String]? {
        guard case .array(let items) = value, !items.isEmpty else { return nil }
        let strings = items.compactMap { item -> String? in if case .string(let s) = item { s } else { nil } }
        return strings.count == items.count ? strings : nil
    }

    /// Reads a list of actions, skipping the ones that cannot be used.
    public static func list(_ value: ConfigValue?, at path: String, problems: inout [String]) -> [PluginAction] {
        guard let value else { return [] }
        guard case .array(let items) = value else {
            problems.append("\(path) must be a list")
            return []
        }
        var seen: Set<String> = []
        return items.enumerated().compactMap { index, item in
            let here = "\(path)[\(index)]"
            guard case .table(let table) = item else {
                problems.append("\(here) must be an object")
                return nil
            }
            guard case .string(let id)? = table["id"], isValidID(id), case .string(let title)? = table["title"], !title.isEmpty,
                  let command = table["command"].flatMap(command) else {
                problems.append("\(here) needs an id, a title and a command (a list of strings)")
                return nil
            }
            var context = Context.global
            if let raw = table["context"] {
                guard case .string(let name) = raw, let parsed = Context(rawValue: name) else {
                    problems.append("\(here).context must be \"global\", \"project\" or \"agent\"")
                    return nil
                }
                context = parsed
            }
            guard seen.insert(id).inserted else {
                problems.append("\(here): id \"\(id)\" is used twice")
                return nil
            }
            let symbol = if case .string(let symbol)? = table["symbol"] { symbol } else { String?.none }
            return PluginAction(id: id, title: title, context: context, command: command, symbol: symbol)
        }
    }
}

/// A loaded plugin: its manifest and the folder its commands run from.
public struct Plugin: Sendable, Equatable, Identifiable {
    public let manifest: PluginManifest
    public let folder: URL

    public init(manifest: PluginManifest, folder: URL) {
        self.manifest = manifest
        self.folder = folder
    }

    public var id: String { manifest.id }
}

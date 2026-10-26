import Foundation

/// Which sources Shepherd runs, in herd order, and how the tmux source reads each agent's screen.
public struct SourcesConfig: Sendable, Equatable {
    /// The sources Shepherd knows, in the order they run when `sources` is left out.
    public static let known = ["herdr", "report", "tmux"]

    /// Source ids in order. Agents and projects are grouped by source in this order.
    public var order: [String]
    /// How tmux tells each agent kind and its state from a pane's screen.
    public var screens: [String: ScreenPatterns]

    public init(order: [String] = SourcesConfig.known, screens: [String: ScreenPatterns] = ScreenPatterns.builtin) {
        self.order = order
        self.screens = screens
    }

    /// Reads `sources`: a list of source ids, or objects with a `source` id and that source's
    /// settings. Only tmux has settings: `agents`, screen patterns by agent kind, each replacing
    /// the built-in kind of that name or adding one.
    static func read(_ value: ConfigValue, problems: inout [String]) -> SourcesConfig {
        guard case .array(let entries) = value else {
            problems.append("config: sources must be a list of source ids or objects")
            return SourcesConfig()
        }
        var config = SourcesConfig(order: [])
        for (index, entry) in entries.enumerated() {
            let at = "sources[\(index)]"
            let id: String
            var settings: [String: ConfigValue] = [:]
            switch entry {
            case .string(let name):
                id = name
            case .table(let table):
                guard case .string(let name)? = table["source"] else {
                    problems.append("config: \(at).source must be a source id")
                    continue
                }
                id = name
                settings = table.filter { $0.key != "source" }
            default:
                problems.append("config: \(at) must be a source id or an object")
                continue
            }
            guard known.contains(id) else {
                problems.append("config: \(at): unknown source \"\(id)\"; known: \(known.joined(separator: ", "))")
                continue
            }
            guard !config.order.contains(id) else {
                problems.append("config: \(at): \"\(id)\" is listed twice")
                continue
            }
            config.order.append(id)
            let allowed = id == "tmux" ? ["agents"] : []
            for key in settings.keys.sorted() where !allowed.contains(key) {
                problems.append("config: unknown key \"\(at).\(key)\"")
            }
            if id == "tmux", let agents = settings["agents"] {
                readAgents(agents, at: "\(at).agents", into: &config.screens, problems: &problems)
            }
        }
        if config.order.isEmpty { problems.append("config: sources lists no source, so no agents will show") }
        return config
    }

    private static func readAgents(_ value: ConfigValue, at path: String, into screens: inout [String: ScreenPatterns],
                                   problems: inout [String]) {
        guard case .table(let kinds) = value else {
            problems.append("config: \(path) must be an object of agent kinds")
            return
        }
        var added: [String: ScreenPatterns] = [:]
        for kind in kinds.keys.sorted() {
            do {
                let patterns = try ScreenPatterns.read(kinds[kind]!, kind: kind, at: "\(path).\(kind)", problems: &problems)
                if let other = added.first(where: { $0.value.process == patterns.process })?.key {
                    problems.append("config: \(path).\(kind): process \"\(patterns.process)\" is already \(path).\(other)")
                    continue
                }
                added[kind] = patterns
            } catch {
                problems.append("config: \(error.message)")
            }
        }
        // A kind from config wins over a built-in one watching the same process.
        let processes = Set(added.values.map(\.process))
        screens = screens.filter { !processes.contains($0.value.process) }.merging(added) { $1 }
    }
}

/// What a pane's screen shows for one agent kind. Each state is a list of regular expressions,
/// matched against the last lines of the screen (trimmed, one per line, empty lines left out):
/// the state applies when every one of them is found. Blocked wins over working, working over
/// idle; a screen matching none is unknown. A numbered choice on screen is blocked for every kind.
public struct ScreenPatterns: Sendable, Equatable {
    /// The process name that makes a pane this agent; by default the kind itself.
    public var process: String
    public var blocked: [String]
    public var working: [String]
    public var idle: [String]

    public init(process: String, blocked: [String] = [], working: [String] = [], idle: [String] = []) {
        self.process = process
        self.blocked = blocked
        self.working = working
        self.idle = idle
    }

    /// Checked against Claude Code 2.1.299 and Codex 0.162.1. `esc to interrupt` shows while a
    /// turn runs. Claude's idle input line sits between two rules (a trust prompt has a `❯` cursor
    /// too, but no rules around it); Codex's idle screen has its `›` input and the shortcuts hint.
    public static let builtin: [String: ScreenPatterns] = [
        "claude": ScreenPatterns(process: "claude", working: ["esc to interrupt"],
                                 idle: ["(?m)^────.*\\n❯.*\\n────"]),
        "codex": ScreenPatterns(process: "codex", working: ["esc to interrupt"],
                                idle: ["(?m)^›", "\\? for shortcuts"]),
    ]

    /// An unknown key is a problem but the kind still applies; a value that cannot be used drops the kind.
    static func read(_ value: ConfigValue, kind: String, at path: String,
                     problems: inout [String]) throws(ConfigProblem) -> ScreenPatterns {
        guard case .table(let table) = value else { throw ConfigProblem("\(path) must be an object") }
        for key in table.keys.sorted() where !["process", "blocked", "working", "idle"].contains(key) {
            problems.append("config: unknown key \"\(path).\(key)\"")
        }
        var patterns = ScreenPatterns(process: kind)
        switch table["process"] {
        case nil: break
        case .string(let name)? where !name.isEmpty: patterns.process = name
        default: throw ConfigProblem("\(path).process must be a process name")
        }
        for (key, field) in [("blocked", \ScreenPatterns.blocked), ("working", \.working), ("idle", \.idle)] {
            guard let list = table[key] else { continue }
            let items = if case .array(let items) = list { items } else { [ConfigValue]() }
            let strings = items.compactMap { item -> String? in if case .string(let text) = item { text } else { nil } }
            guard case .array = list, strings.count == items.count else {
                throw ConfigProblem("\(path).\(key) must be a list of regular expressions")
            }
            for pattern in strings {
                do {
                    _ = try NSRegularExpression(pattern: pattern)
                } catch {
                    throw ConfigProblem("\(path).\(key): \"\(pattern)\" is not a valid regular expression")
                }
            }
            patterns[keyPath: field] = strings
        }
        return patterns
    }
}

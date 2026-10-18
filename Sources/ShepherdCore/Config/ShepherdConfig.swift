import Foundation

/// Shepherd's config file. Every key is optional and a missing file means defaults. Reading is
/// lenient per key: a key that cannot be used is reported and falls back to its default, and the
/// rest still applies.
public struct ShepherdConfig: Sendable, Equatable {
    public static let defaultNextHotkey = "ctrl+option+cmd+n"
    public static let defaultPaletteHotkey = "option+space"

    /// Enabled module ids in order; nil means every built-in module in default order.
    public var modules: [String]?
    /// Token layouts; a section left out falls through to the source's layout.
    public var tokens: TokenLayout
    /// The global "next" hotkey; nil turns it off.
    public var nextHotkey: String?
    /// The global hotkey that opens the palette; nil turns it off.
    public var paletteHotkey: String?
    /// Per agent kind ("claude", "codex"), how Shepherd starts it for a new task.
    public var agents: [String: AgentConfig]
    /// When Shepherd posts system notifications. Off by default: the notch is the alert, and
    /// nothing asks for permission until the user turns them on.
    public var notifications: Notifications
    /// Plugin ids to skip. Every plugin in the plugins folder is on otherwise.
    public var disabledPlugins: [String]

    public enum Notifications: String, Sendable, Equatable, CaseIterable {
        /// Unless a source already posts its own (herdr with `ui.toast.delivery` "system" or
        /// "terminal").
        case auto
        case on
        case off
    }

    public struct AgentConfig: Sendable, Equatable {
        /// Arguments after the agent's command, such as `--dangerously-skip-permissions`.
        public var args: [String]

        public init(args: [String] = []) {
            self.args = args
        }
    }

    public init(modules: [String]? = nil, tokens: TokenLayout = TokenLayout(),
                nextHotkey: String? = ShepherdConfig.defaultNextHotkey,
                paletteHotkey: String? = ShepherdConfig.defaultPaletteHotkey, agents: [String: AgentConfig] = [:],
                notifications: Notifications = .off, disabledPlugins: [String] = []) {
        self.modules = modules
        self.tokens = tokens
        self.nextHotkey = nextHotkey
        self.paletteHotkey = paletteHotkey
        self.agents = agents
        self.notifications = notifications
        self.disabledPlugins = disabledPlugins
    }

    public static let defaults = ShepherdConfig()

    /// `SHEPHERD_CONFIG_PATH`, else `~/.config/shepherd/config.json`.
    public static func defaultURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let path = environment["SHEPHERD_CONFIG_PATH"], !path.isEmpty { return URL(fileURLWithPath: path) }
        return FileManager.default.homeDirectoryForCurrentUser.appending(path: ".config/shepherd/config.json")
    }

    /// Reads the file's contents. Throws only when the file as a whole cannot be read (not JSON,
    /// or not an object); anything smaller is a problem in the result.
    public static func read(_ data: Data) throws(ConfigProblem) -> (config: ShepherdConfig, problems: [String]) {
        let value: ConfigValue
        do {
            value = try JSONDecoder().decode(ConfigValue.self, from: data)
        } catch {
            throw ConfigProblem("config.json is not valid JSON: \(describe(error))")
        }
        guard case .table(let table) = value else { throw ConfigProblem("config.json must be an object") }

        var config = ShepherdConfig()
        var problems: [String] = []
        for key in table.keys.sorted() where !["modules", "tokens", "hotkeys", "agents", "notifications", "plugins"].contains(key) {
            problems.append("config: unknown key \"\(key)\"")
        }
        if let modules = table["modules"] {
            let items = if case .array(let items) = modules { items } else { [ConfigValue]() }
            let ids = items.compactMap { item -> String? in if case .string(let id) = item { id } else { nil } }
            if case .array = modules, ids.count == items.count {
                config.modules = ids
            } else {
                problems.append("config: modules must be a list of module ids")
            }
        }
        if let tokens = table["tokens"] {
            if case .table(let sections) = tokens {
                for key in sections.keys.sorted() where TokenLayout.Section(rawValue: key) == nil {
                    problems.append("config: unknown key \"tokens.\(key)\"")
                }
                for section in TokenLayout.Section.allCases {
                    guard let rows = sections[section.rawValue] else { continue }
                    do {
                        let parsed = try TokenLayout.rows(rows, at: "tokens.\(section.rawValue)")
                        switch section {
                        case .projects: config.tokens.projects = parsed
                        case .agents: config.tokens.agents = parsed
                        }
                    } catch {
                        problems.append("config: \(error.message)")
                    }
                }
            } else {
                problems.append("config: tokens must be an object with projects and agents")
            }
        }
        if let hotkeys = table["hotkeys"] {
            if case .table(let keys) = hotkeys {
                for key in keys.keys.sorted() where !["next", "palette"].contains(key) {
                    problems.append("config: unknown key \"hotkeys.\(key)\"")
                }
                for (name, path) in [("next", \ShepherdConfig.nextHotkey), ("palette", \ShepherdConfig.paletteHotkey)] {
                    switch keys[name] {
                    case nil: break
                    case .null?: config[keyPath: path] = nil
                    case .string(let combo)?: config[keyPath: path] = combo
                    case let other?: problems.append("config: hotkeys.\(name) must be a string or null, found \(other.kind)")
                    }
                }
            } else {
                problems.append("config: hotkeys must be an object")
            }
        }
        if let agents = table["agents"] {
            if case .table(let kinds) = agents {
                for kind in kinds.keys.sorted() {
                    guard case .table(let settings) = kinds[kind] else {
                        problems.append("config: agents.\(kind) must be an object")
                        continue
                    }
                    for key in settings.keys.sorted() where key != "args" {
                        problems.append("config: unknown key \"agents.\(kind).\(key)\"")
                    }
                    guard let args = settings["args"] else { continue }
                    let items = if case .array(let items) = args { items } else { [ConfigValue]() }
                    let strings = items.compactMap { item -> String? in if case .string(let arg) = item { arg } else { nil } }
                    if case .array = args, strings.count == items.count {
                        config.agents[kind] = AgentConfig(args: strings)
                    } else {
                        problems.append("config: agents.\(kind).args must be a list of strings")
                    }
                }
            } else {
                problems.append("config: agents must be an object of agent kinds")
            }
        }
        if let notifications = table["notifications"] {
            if case .string(let mode) = notifications, let value = Notifications(rawValue: mode) {
                config.notifications = value
            } else {
                problems.append("config: notifications must be \"auto\", \"on\" or \"off\"")
            }
        }
        if let plugins = table["plugins"] {
            if case .table(let keys) = plugins {
                for key in keys.keys.sorted() where key != "disabled" {
                    problems.append("config: unknown key \"plugins.\(key)\"")
                }
                if let disabled = keys["disabled"] {
                    let items = if case .array(let items) = disabled { items } else { [ConfigValue]() }
                    let ids = items.compactMap { item -> String? in if case .string(let id) = item { id } else { nil } }
                    if case .array = disabled, ids.count == items.count {
                        config.disabledPlugins = ids
                    } else {
                        problems.append("config: plugins.disabled must be a list of plugin ids")
                    }
                }
            } else {
                problems.append("config: plugins must be an object")
            }
        }
        return (config, problems)
    }

    /// The useful part of a decoding error: Foundation's own message, which names the line.
    private static func describe(_ error: any Error) -> String {
        if case DecodingError.dataCorrupted(let context) = error {
            let underlying = (context.underlyingError as NSError?)?.userInfo[NSDebugDescriptionErrorKey] as? String
            return underlying ?? context.debugDescription
        }
        return error.localizedDescription
    }
}

import Foundation

/// Shepherd's config file. Every key is optional and a missing file means defaults. Reading is
/// lenient per key: a key that cannot be used is reported and falls back to its default, and the
/// rest still applies.
public struct ShepherdConfig: Sendable, Equatable {
    public static let defaultNextHotkey = "ctrl+option+cmd+n"

    /// Enabled module ids in order; nil means every built-in module in default order.
    public var modules: [String]?
    /// Token layouts; a section left out falls through to the source's layout.
    public var tokens: TokenLayout
    /// The global "next" hotkey; nil turns it off.
    public var nextHotkey: String?

    public init(modules: [String]? = nil, tokens: TokenLayout = TokenLayout(),
                nextHotkey: String? = ShepherdConfig.defaultNextHotkey) {
        self.modules = modules
        self.tokens = tokens
        self.nextHotkey = nextHotkey
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
        for key in table.keys.sorted() where !["modules", "tokens", "hotkeys"].contains(key) {
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
                for key in keys.keys.sorted() where key != "next" { problems.append("config: unknown key \"hotkeys.\(key)\"") }
                switch keys["next"] {
                case nil: break
                case .null?: config.nextHotkey = nil
                case .string(let combo)?: config.nextHotkey = combo
                case let other?: problems.append("config: hotkeys.next must be a string or null, found \(other.kind)")
                }
            } else {
                problems.append("config: hotkeys must be an object")
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

import Foundation
import ShepherdCore

/// Reads the token layout from herdr's own sidebar config, so a herdr user's colours and rules
/// apply in Shepherd with no setup. Space rows (`ui.sidebar.spaces.rows`) style projects, agent
/// rows (`ui.sidebar.agents.rows`) style agents. Only plugin tokens (`$name`) are taken: Shepherd
/// draws herdr's built-ins (state, workspace, branch) its own way. `rows_by_agent` is not read yet.
public enum HerdrSidebar {
    /// `HERDR_CONFIG_PATH`, else `~/.config/herdr/config.toml`, as herdr resolves it.
    public static func configURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let path = environment["HERDR_CONFIG_PATH"], !path.isEmpty { return URL(fileURLWithPath: path) }
        return FileManager.default.homeDirectoryForCurrentUser.appending(path: ".config/herdr/config.toml")
    }

    /// The layout (nil when herdr's config sets no rows) and problems worth showing, such as
    /// "herdr config line 79: …". A missing file is no layout and no problem.
    static func read(_ data: Data?) -> (layout: TokenLayout?, problems: [String]) {
        guard let data else { return (nil, []) }
        let document = TOMLDocument(data)
        var problems = document.problems.map { "herdr config line \($0.line): \($0.message)" }
        var layout = TokenLayout()
        for (section, key) in [(TokenLayout.Section.projects, "spaces"), (.agents, "agents")] {
            guard let (value, line) = document.value(at: ["ui", "sidebar", key, "rows"]) else { continue }
            do {
                let rows = try TokenLayout.rows(pluginTokensOnly(configValue(value)), at: "ui.sidebar.\(key).rows")
                switch section {
                case .projects: layout.projects = rows
                case .agents: layout.agents = rows
                }
            } catch {
                problems.append("herdr config line \(line): \(error.message)")
            }
        }
        return (layout == TokenLayout() ? nil : layout, problems)
    }

    /// Drops built-in entries: in herdr a bare name is always a built-in.
    static func pluginTokensOnly(_ rows: ConfigValue) -> ConfigValue {
        guard case .array(let lines) = rows else { return rows }
        return .array(lines.map { line in
            guard case .array(let entries) = line else { return line }
            return .array(entries.filter { entry in
                switch entry {
                case .string(let name): name.hasPrefix("$")
                case .table(let table): if case .string(let name)? = table["token"] { name.hasPrefix("$") } else { true }
                default: true
                }
            })
        })
    }

    static func configValue(_ value: TOMLDocument.Value) -> ConfigValue {
        switch value {
        case .string(let text): .string(text)
        case .integer(let number): .number(Double(number))
        case .float(let number): .number(number)
        case .bool(let flag): .bool(flag)
        case .array(let items): .array(items.map(configValue))
        case .table(let table): .table(table.mapValues(configValue))
        case .opaque: .null
        }
    }
}

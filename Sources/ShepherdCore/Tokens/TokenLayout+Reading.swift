// Builds token layouts from config values with herdr's validation: a rule has exactly one
// condition, `gt`/`lt` take finite numbers, `fg` is `#RGB` or `#RRGGBB`, at most 16 rules.

extension TokenLayout {
    public enum Section: String, Sendable, CaseIterable {
        case projects, agents
    }

    public subscript(section: Section) -> [[TokenEntry]]? {
        switch section {
        case .projects: projects
        case .agents: agents
        }
    }

    /// The lines for one section. A layout replaces rather than merges, so the first layout that
    /// defines the section wins: Shepherd's config, then the source's own, then every token on
    /// one line, sorted by name.
    public static func lines(_ section: Section, values: [String: String], layouts: [TokenLayout?]) -> [[StyledToken]] {
        let layout = layouts.lazy.compactMap { $0?[section] }.first ?? TokenStyler.defaultLayout(for: values)
        return TokenStyler.lines(layout, values: values)
    }

    /// Reads `{ "projects": rows, "agents": rows }`; an absent section stays nil.
    public init(_ value: ConfigValue) throws(ConfigProblem) {
        guard case .table(let table) = value else { throw ConfigProblem("expected an object, found \(value.kind)") }
        self.init(projects: try table["projects"].map { v throws(ConfigProblem) in try Self.rows(v, at: "projects") },
                  agents: try table["agents"].map { v throws(ConfigProblem) in try Self.rows(v, at: "agents") })
    }

    /// A list of lines, each a list of entries.
    public static func rows(_ value: ConfigValue, at path: String) throws(ConfigProblem) -> [[TokenEntry]] {
        guard case .array(let lines) = value else { throw ConfigProblem("\(path): expected a list of lines, found \(value.kind)") }
        var result: [[TokenEntry]] = []
        for (index, line) in lines.enumerated() {
            guard case .array(let entries) = line else {
                throw ConfigProblem("\(path)[\(index)]: expected a list of tokens, found \(line.kind)")
            }
            var parsed: [TokenEntry] = []
            for (position, entry) in entries.enumerated() {
                parsed.append(try TokenEntry(entry, at: "\(path)[\(index)][\(position)]"))
            }
            result.append(parsed)
        }
        return result
    }
}

extension TokenEntry {
    /// `"pr"`, `"$pr"` or `{ token, fg, bold, dim, rules }`.
    public init(_ value: ConfigValue, at path: String) throws(ConfigProblem) {
        switch value {
        case .string(let written):
            let (name, builtin) = Self.parse(name: written)
            self.init(name: name, isBuiltin: builtin)
        case .table(let table):
            guard case .string(let written)? = table["token"] else { throw ConfigProblem("\(path): missing \"token\"") }
            let (name, builtin) = Self.parse(name: written)
            var rules: [TokenRule] = []
            if let list = table["rules"] {
                guard case .array(let items) = list else { throw ConfigProblem("\(path).rules: expected a list, found \(list.kind)") }
                guard items.count <= Self.maximumRules else {
                    throw ConfigProblem("\(path).rules: at most \(Self.maximumRules) rules")
                }
                for (index, item) in items.enumerated() {
                    rules.append(try TokenRule(item, at: "\(path).rules[\(index)]"))
                }
            }
            self.init(name: name, isBuiltin: builtin, style: try TokenStyle(table, at: path), rules: rules)
        default:
            throw ConfigProblem("\(path): expected a token name or an object, found \(value.kind)")
        }
    }
}

extension TokenStyle {
    init(_ table: [String: ConfigValue], at path: String) throws(ConfigProblem) {
        func flag(_ key: String) throws(ConfigProblem) -> Bool? {
            guard let value = table[key] else { return nil }
            guard case .bool(let flag) = value else { throw ConfigProblem("\(path).\(key): expected true or false") }
            return flag
        }
        var fg: HexColor?
        if let value = table["fg"] {
            guard case .string(let text) = value, let color = HexColor(text) else {
                throw ConfigProblem("\(path).fg: must be #RGB or #RRGGBB")
            }
            fg = color
        }
        self.init(fg: fg, bold: try flag("bold"), dim: try flag("dim"))
    }
}

extension TokenRule {
    static let conditionKeys = ["equals", "contains", "starts_with", "gt", "lt"]

    init(_ value: ConfigValue, at path: String) throws(ConfigProblem) {
        guard case .table(let table) = value else { throw ConfigProblem("\(path): expected an object, found \(value.kind)") }
        let present = Self.conditionKeys.filter { table[$0] != nil }
        guard present.count == 1, let key = present.first, let operand = table[key] else {
            throw ConfigProblem("\(path): needs exactly one of equals, contains, starts_with, gt, lt")
        }
        let condition: TokenCondition
        switch (key, operand) {
        case ("equals", .string(let text)): condition = .equals(text)
        case ("contains", .string(let text)): condition = .contains(text)
        case ("starts_with", .string(let text)): condition = .startsWith(text)
        case ("gt", .number(let number)) where number.isFinite: condition = .greaterThan(number)
        case ("lt", .number(let number)) where number.isFinite: condition = .lessThan(number)
        case ("gt", _), ("lt", _): throw ConfigProblem("\(path).\(key): expected a number")
        default: throw ConfigProblem("\(path).\(key): expected a string")
        }
        var ignoreCase = false
        if let value = table["ignore_case"] {
            guard case .bool(let flag) = value else { throw ConfigProblem("\(path).ignore_case: expected true or false") }
            ignoreCase = flag
        }
        var hide = false
        if let value = table["hide"] {
            guard case .bool(let flag) = value else { throw ConfigProblem("\(path).hide: expected true or false") }
            hide = flag
        }
        self.init(condition, ignoreCase: ignoreCase, style: try TokenStyle(table, at: path), hide: hide)
    }
}

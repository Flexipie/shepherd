/// A token value ready to draw.
public struct StyledToken: Sendable, Equatable {
    public let name: String
    public let text: String
    public let fg: HexColor?
    public let bold: Bool
    public let dim: Bool

    public init(name: String, text: String, fg: HexColor? = nil, bold: Bool = false, dim: Bool = false) {
        self.name = name
        self.text = text
        self.fg = fg
        self.bold = bold
        self.dim = dim
    }
}

/// Applies a layout to token values with herdr's sidebar semantics: per entry, the first matching
/// rule wins and its unset fields inherit the entry's; `hide` removes the token; a missing or
/// empty token disappears, and so does a line left empty.
public enum TokenStyler {
    public static func lines(_ layout: [[TokenEntry]], values: [String: String]) -> [[StyledToken]] {
        layout.compactMap { line in
            let tokens = line.compactMap { style($0, values: values) }
            return tokens.isEmpty ? nil : tokens
        }
    }

    static func style(_ entry: TokenEntry, values: [String: String]) -> StyledToken? {
        guard !entry.isBuiltin, let value = values[entry.name], !value.isEmpty else { return nil }
        var style = entry.style
        if let rule = entry.rules.first(where: { $0.matches(value) }) {
            if rule.hide { return nil }
            style = style.overridden(by: rule.style)
        }
        return StyledToken(name: entry.name, text: value, fg: style.fg, bold: style.bold ?? false, dim: style.dim ?? false)
    }

    /// Every token on one line, sorted by name, unstyled: what shows when no layout covers a section.
    public static func defaultLayout(for values: [String: String]) -> [[TokenEntry]] {
        [values.keys.sorted().map { TokenEntry(name: $0) }]
    }
}

import Foundation

/// How tokens are laid out and styled, in herdr's sidebar rule syntax: each section is a list of
/// lines, each line a list of entries. `projects` styles a project's tokens, `agents` an agent's.
/// A section is nil when this layout does not define it, so another layout's section applies.
public struct TokenLayout: Sendable, Equatable {
    public var projects: [[TokenEntry]]?
    public var agents: [[TokenEntry]]?

    public init(projects: [[TokenEntry]]? = nil, agents: [[TokenEntry]]? = nil) {
        self.projects = projects
        self.agents = agents
    }
}

/// One token on a line: its name, default style and rules.
public struct TokenEntry: Sendable, Equatable {
    /// herdr's built-in sidebar tokens. Shepherd draws these itself, so layouts skip them.
    public static let builtinNames: Set<String> = [
        "state_icon", "state_text", "machine", "workspace", "tab", "agent", "terminal_title",
        "terminal_title_stripped", "branch", "git_status",
    ]
    /// herdr's limit.
    public static let maximumRules = 16

    /// The token name without `$`.
    public let name: String
    /// A herdr built-in, not a plugin token.
    public let isBuiltin: Bool
    public let style: TokenStyle
    public let rules: [TokenRule]

    public init(name: String, isBuiltin: Bool = false, style: TokenStyle = TokenStyle(), rules: [TokenRule] = []) {
        self.name = name
        self.isBuiltin = isBuiltin
        self.style = style
        self.rules = rules
    }

    /// Parses a name as written in config: `$pr` and `pr` both mean the plugin token `pr`, except
    /// that a bare built-in name (`branch`) means the built-in.
    public static func parse(name written: String) -> (name: String, isBuiltin: Bool) {
        if written.hasPrefix("$") { return (String(written.dropFirst()), false) }
        return (written, builtinNames.contains(written))
    }
}

/// Style overrides. Unset fields inherit.
public struct TokenStyle: Sendable, Equatable {
    public var fg: HexColor?
    public var bold: Bool?
    public var dim: Bool?

    public init(fg: HexColor? = nil, bold: Bool? = nil, dim: Bool? = nil) {
        self.fg = fg
        self.bold = bold
        self.dim = dim
    }

    /// `self` with `other`'s set fields on top.
    public func overridden(by other: TokenStyle) -> TokenStyle {
        TokenStyle(fg: other.fg ?? fg, bold: other.bold ?? bold, dim: other.dim ?? dim)
    }
}

/// A rule: one condition and what to change when it matches. A rule with no overrides still
/// stops later rules from matching.
public struct TokenRule: Sendable, Equatable {
    public let condition: TokenCondition
    /// ASCII only, as in herdr. Applies to the string conditions.
    public let ignoreCase: Bool
    public let style: TokenStyle
    public let hide: Bool

    public init(_ condition: TokenCondition, ignoreCase: Bool = false, style: TokenStyle = TokenStyle(), hide: Bool = false) {
        self.condition = condition
        self.ignoreCase = ignoreCase
        self.style = style
        self.hide = hide
    }

    public func matches(_ value: String) -> Bool {
        switch condition {
        case .equals(let text): fold(value) == fold(text)
        case .contains(let text): fold(value).contains(fold(text))
        case .startsWith(let text): fold(value).hasPrefix(fold(text))
        case .greaterThan(let limit): TokenRule.number(value).map { $0 > limit } ?? false
        case .lessThan(let limit): TokenRule.number(value).map { $0 < limit } ?? false
        }
    }

    private func fold(_ text: String) -> String {
        guard ignoreCase else { return text }
        return String(String.UnicodeScalarView(text.unicodeScalars.map { scalar in
            ("A"..."Z").contains(scalar) ? Unicode.Scalar(scalar.value + 32)! : scalar
        }))
    }

    /// The whole value as a finite decimal number, or nil: "90" and "-1.5e3" parse, "90%", " 90",
    /// "inf" and "0x10" do not.
    static func number(_ value: String) -> Double? {
        var scalars = Substring(value).unicodeScalars[...]
        func digits() -> Int {
            var count = 0
            while let first = scalars.first, ("0"..."9").contains(first) {
                scalars.removeFirst()
                count += 1
            }
            return count
        }
        if let first = scalars.first, first == "+" || first == "-" { scalars.removeFirst() }
        var mantissa = digits()
        if scalars.first == "." {
            scalars.removeFirst()
            mantissa += digits()
        }
        guard mantissa > 0 else { return nil }
        if let first = scalars.first, first == "e" || first == "E" {
            scalars.removeFirst()
            if let sign = scalars.first, sign == "+" || sign == "-" { scalars.removeFirst() }
            guard digits() > 0 else { return nil }
        }
        guard scalars.isEmpty, let number = Double(value), number.isFinite else { return nil }
        return number
    }
}

public enum TokenCondition: Sendable, Equatable {
    case equals(String)
    case contains(String)
    case startsWith(String)
    case greaterThan(Double)
    case lessThan(Double)
}

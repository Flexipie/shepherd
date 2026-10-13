import Foundation

/// One numbered choice an agent offers, such as "1. Yes" in an approval prompt.
public struct AgentChoice: Sendable, Equatable {
    /// The key that picks it, such as "1".
    public let key: String
    public let label: String
    /// The choice the agent's cursor is on, which Return would pick.
    public let isSelected: Bool

    public init(key: String, label: String, isSelected: Bool = false) {
        self.key = key
        self.label = label
        self.isSelected = isSelected
    }
}

/// Finds the choices in an agent's visible lines: the last run of options numbered 1, 2, 3...,
/// one of them under the agent's cursor (`❯`, `›` or `>`), as Claude Code and
/// Codex draw approval prompts. The cursor is required so a numbered list in the agent's output
/// is not mistaken for a prompt. Box borders are ignored; an option's wrapped second line is
/// left out of its label. Anything else gives no choices, and the surface falls back to Return,
/// Escape and a reply.
public enum ChoiceParser {
    /// How many lines may sit between two options (a wrapped label) and still be one run.
    static let maxGap = 2

    public static func choices(in text: String) -> [AgentChoice] {
        let options = text.split(separator: "\n", omittingEmptySubsequences: false).enumerated().compactMap { index, line in
            option(String(line)).map { (index, $0) }
        }
        var run: [(line: Int, choice: AgentChoice)] = []
        var best: [(line: Int, choice: AgentChoice)] = []
        for (line, choice) in options {
            let continues = run.last.map { Int(choice.key) == Int($0.choice.key)! + 1 && line - $0.line <= maxGap + 1 } ?? false
            if continues {
                run.append((line, choice))
            } else {
                if isPrompt(run) { best = run }
                run = choice.key == "1" ? [(line, choice)] : []
            }
        }
        if isPrompt(run) { best = run }
        return best.map(\.choice)
    }

    private static func isPrompt(_ run: [(line: Int, choice: AgentChoice)]) -> Bool {
        run.count >= 2 && run.contains { $0.choice.isSelected }
    }

    /// `❯ 1. Yes`, `  2. No (esc)`, `│ › 1. Yes, proceed (y) │`: a cursor or not, a digit, a dot
    /// or bracket, a label.
    static func option(_ line: String) -> AgentChoice? {
        var rest = Substring(line).drop { $0.isWhitespace || isBorder($0) }
        var selected = false
        if let first = rest.first, cursors.contains(first) {
            selected = true
            rest = rest.dropFirst().drop(while: \.isWhitespace)
        }
        guard let digit = rest.first, digit.isASCII, digit.isNumber, digit != "0" else { return nil }
        rest = rest.dropFirst()
        guard let mark = rest.first, mark == "." || mark == ")" else { return nil }
        rest = rest.dropFirst()
        guard rest.first?.isWhitespace == true else { return nil }
        let label = rest.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "│┃|"))
            .trimmingCharacters(in: .whitespaces)
        guard !label.isEmpty else { return nil }
        return AgentChoice(key: String(digit), label: label, isSelected: selected)
    }

    static let cursors: Set<Character> = ["❯", "›", ">", "▶", "→"]

    private static func isBorder(_ character: Character) -> Bool {
        "│┃|".contains(character)
    }
}

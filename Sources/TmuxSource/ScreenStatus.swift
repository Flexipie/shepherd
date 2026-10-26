import ShepherdCore

/// What a pane's visible screen says about the agent in it. Pure: screen text in, a status out.
/// The markers were checked against the agents' own screens (Claude Code 2.1.299, Codex 0.162.1):
/// an approval or trust prompt, the `esc to interrupt` hint while a turn runs, and the idle input
/// line. Anything else is unknown, so a screen Shepherd does not recognise never shows as idle.
enum ScreenStatus {
    /// The agent kinds read from the screen, matched by process name. Shipped in code; config can
    /// add more when the sources-in-config step lands.
    static let kinds: Set<String> = ["claude", "codex"]

    /// The last non-empty lines the working and idle markers are read from. An old line higher up
    /// in the transcript does not count.
    static let footerLines = 10

    static func status(kind: String, screen: String) -> HerdStatus {
        // A prompt waiting for an answer is on the screen while the agent blocks, and nothing else is.
        if !ChoiceParser.choices(in: screen).isEmpty { return .blocked }
        let footer = nonEmptyLines(screen).suffix(footerLines).map { $0.trimmingCharacters(in: .whitespaces) }
        if footer.contains(where: { $0.contains("esc to interrupt") }) { return .working }
        return isIdle(kind: kind, footer: footer) ? .idle : .unknown
    }

    private static func isIdle(kind: String, footer: [String]) -> Bool {
        switch kind {
        case "claude":
            // The input line sits between two rules. A trust prompt has a `❯` cursor too, but no rules around it.
            return footer.indices.contains { index in
                footer[index].hasPrefix("❯") && index > 0 && index + 1 < footer.count
                    && isRule(footer[index - 1]) && isRule(footer[index + 1])
            }
        case "codex":
            return footer.contains { $0.hasPrefix("›") } && footer.contains { $0.contains("? for shortcuts") }
        default:
            return false
        }
    }

    private static func isRule(_ line: String) -> Bool {
        line.hasPrefix("────")
    }

    private static func nonEmptyLines(_ screen: String) -> [String] {
        screen.split(separator: "\n", omittingEmptySubsequences: true).map(String.init).filter {
            !$0.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }
}

import Foundation
import ShepherdCore

/// What a pane's visible screen says about the agent in it. Pure: screen text in, a status out.
/// The patterns come from config (`ScreenPatterns`, with built-in ones for Claude Code and Codex).
/// A prompt waiting for an answer is blocked for any kind; otherwise the kind's patterns decide,
/// and anything else is unknown, so a screen Shepherd does not recognise never shows as idle.
struct ScreenStatus: Sendable {
    /// The last non-empty lines the patterns are read from. An old line higher up in the
    /// transcript does not count.
    static let footerLines = 10

    private struct Kind: @unchecked Sendable {
        // NSRegularExpression is immutable and safe to share across threads.
        let blocked: [NSRegularExpression]
        let working: [NSRegularExpression]
        let idle: [NSRegularExpression]
    }

    private let kinds: [String: Kind]
    /// Agent kinds by the process name that makes a pane that agent.
    let kindByProcess: [String: String]

    /// Patterns that do not compile are left out; config reading has already said so.
    init(_ patterns: [String: ScreenPatterns] = ScreenPatterns.builtin) {
        func compile(_ list: [String]) -> [NSRegularExpression]? {
            let compiled = list.compactMap { try? NSRegularExpression(pattern: $0) }
            return compiled.count == list.count ? compiled : nil
        }
        var kinds: [String: Kind] = [:]
        var byProcess: [String: String] = [:]
        for name in patterns.keys.sorted() {
            let pattern = patterns[name]!
            guard let blocked = compile(pattern.blocked), let working = compile(pattern.working),
                  let idle = compile(pattern.idle) else { continue }
            kinds[name] = Kind(blocked: blocked, working: working, idle: idle)
            if byProcess[pattern.process] == nil { byProcess[pattern.process] = name }
        }
        self.kinds = kinds
        kindByProcess = byProcess
    }

    func status(kind: String, screen: String) -> HerdStatus {
        // A prompt waiting for an answer is on the screen while the agent blocks, and nothing else is.
        if !ChoiceParser.choices(in: screen).isEmpty { return .blocked }
        guard let patterns = kinds[kind] else { return .unknown }
        let footer = Self.nonEmptyLines(screen).suffix(Self.footerLines)
            .map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n")
        if Self.matches(patterns.blocked, footer) { return .blocked }
        if Self.matches(patterns.working, footer) { return .working }
        if Self.matches(patterns.idle, footer) { return .idle }
        return .unknown
    }

    /// True when the list is not empty and every pattern is found.
    private static func matches(_ patterns: [NSRegularExpression], _ text: String) -> Bool {
        let range = NSRange(text.startIndex..., in: text)
        return !patterns.isEmpty && patterns.allSatisfy { $0.firstMatch(in: text, range: range) != nil }
    }

    private static func nonEmptyLines(_ screen: String) -> [String] {
        screen.split(separator: "\n", omittingEmptySubsequences: true).map(String.init).filter {
            !$0.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }
}

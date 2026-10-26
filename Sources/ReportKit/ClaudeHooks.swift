import Foundation

/// Shepherd's hooks in Claude Code's settings: each runs `shepherd-report report` with the hook's
/// JSON on stdin. Pure: a settings value in, a settings value out. Only hook entries whose command
/// runs `shepherd-report report` (or `shepherd report`) are ever added or removed; every other key,
/// hook and order in the file stays as it was.
public enum ClaudeHooks {
    /// One hook Shepherd installs: the event, its matcher when it takes one, and the status reported.
    struct Entry: Equatable {
        let event: String
        let matcher: String?
        let status: ReportFile.Status
    }

    static let entries: [Entry] = [
        // Not on `compact`: Claude compacts in the middle of work.
        Entry(event: "SessionStart", matcher: "startup|resume|clear", status: .idle),
        Entry(event: "UserPromptSubmit", matcher: nil, status: .working),
        // Back to working once an approved tool has run.
        Entry(event: "PostToolUse", matcher: nil, status: .working),
        // Not `idle_prompt`: Claude waiting at its prompt is done, not blocked.
        Entry(event: "Notification", matcher: "permission_prompt|elicitation_dialog", status: .blocked),
        Entry(event: "Stop", matcher: nil, status: .done),
        Entry(event: "SessionEnd", matcher: nil, status: .closed),
    ]

    public struct Problem: Error, Equatable, CustomStringConvertible {
        public let description: String
    }

    /// The command for a status, running the binary at `executable`.
    static func command(executable: String, status: ReportFile.Status) -> String {
        "\(shellQuoted(executable)) report --status \(status.rawValue) --kind claude --from-hook"
    }

    /// `settings` with Shepherd's hooks in place of any it had. Unchanged when they are already
    /// there exactly, so installing twice changes nothing.
    public static func install(into settings: SettingsJSON, executable: String) throws -> SettingsJSON {
        let wanted = entries.map { ($0.event, $0.matcher, command(executable: executable, status: $0.status)) }
        let present = try ours(in: settings)
        if present.count == wanted.count, zip(present, wanted).allSatisfy({ $0 == $1 }) { return settings }

        guard case var .object(root) = try uninstall(from: settings) else {
            throw Problem(description: "the settings are not a JSON object")
        }
        var hooks: [(key: String, value: SettingsJSON)] = []
        let hooksIndex: Int
        if let index = root.firstIndex(where: { $0.key == "hooks" }) {
            guard case let .object(existing) = root[index].value else { throw Problem(description: "`hooks` is not an object") }
            hooks = existing
            hooksIndex = index
        } else {
            root.append((key: "hooks", value: .object([])))
            hooksIndex = root.count - 1
        }
        for (event, matcher, command) in wanted {
            var group: [(key: String, value: SettingsJSON)] = []
            if let matcher { group.append((key: "matcher", value: .string(matcher))) }
            group.append((key: "hooks", value: .array([.object([
                (key: "type", value: .string("command")),
                (key: "command", value: .string(command)),
            ])])))
            if let index = hooks.firstIndex(where: { $0.key == event }) {
                guard case let .array(groups) = hooks[index].value else {
                    throw Problem(description: "`hooks.\(event)` is not an array")
                }
                hooks[index].value = .array(groups + [.object(group)])
            } else {
                hooks.append((key: event, value: .array([.object(group)])))
            }
        }
        root[hooksIndex].value = .object(hooks)
        return .object(root)
    }

    /// `settings` without Shepherd's hooks. A matcher group, event or `hooks` key that held only
    /// Shepherd's entries goes with them; one that was already empty stays.
    public static func uninstall(from settings: SettingsJSON) throws -> SettingsJSON {
        guard case var .object(root) = settings else { throw Problem(description: "the settings are not a JSON object") }
        guard let hooksIndex = root.firstIndex(where: { $0.key == "hooks" }) else { return settings }
        guard case let .object(events) = root[hooksIndex].value else { throw Problem(description: "`hooks` is not an object") }
        var keptEvents: [(key: String, value: SettingsJSON)] = []
        for (event, value) in events {
            guard case let .array(groups) = value else { keptEvents.append((event, value)); continue }
            var keptGroups: [SettingsJSON] = []
            for group in groups {
                guard case var .object(fields) = group, let index = fields.firstIndex(where: { $0.key == "hooks" }),
                      case let .array(handlers) = fields[index].value else {
                    keptGroups.append(group); continue
                }
                let kept = handlers.filter { !isOurs($0) }
                if kept.count == handlers.count { keptGroups.append(group); continue }
                if kept.isEmpty { continue }
                fields[index].value = .array(kept)
                keptGroups.append(.object(fields))
            }
            if keptGroups.isEmpty, !groups.isEmpty { continue }
            keptEvents.append((event, .array(keptGroups)))
        }
        if keptEvents.isEmpty, !events.isEmpty {
            root.remove(at: hooksIndex)
        } else {
            root[hooksIndex].value = .object(keptEvents)
        }
        return .object(root)
    }

    /// Shepherd's hooks in `settings`, as (event, matcher, command) in file order.
    static func ours(in settings: SettingsJSON) throws -> [(String, String?, String)] {
        guard let hooks = settings["hooks"] else { return [] }
        guard case let .object(events) = hooks else { throw Problem(description: "`hooks` is not an object") }
        var found: [(String, String?, String)] = []
        for (event, value) in events {
            guard case let .array(groups) = value else { continue }
            for group in groups {
                guard case let .array(handlers)? = group["hooks"] else { continue }
                for handler in handlers where isOurs(handler) {
                    found.append((event, group["matcher"]?.string, handler["command"]?.string ?? ""))
                }
            }
        }
        return found
    }

    /// A command hook whose program is named `shepherd-report` or `shepherd`, given `report` first.
    static func isOurs(_ handler: SettingsJSON) -> Bool {
        guard let command = handler["command"]?.string else { return false }
        let words = leadingWords(command, count: 2)
        guard words.count == 2, words[1] == "report" else { return false }
        let program = words[0].split(separator: "/").last.map(String.init) ?? ""
        return program == "shepherd-report" || program == "shepherd"
    }

    /// The first words of a shell command, with single or double quotes around a word removed.
    static func leadingWords(_ command: String, count: Int) -> [String] {
        var words: [String] = []
        var rest = Substring(command)
        while words.count < count {
            rest = rest.drop { $0 == " " || $0 == "\t" }
            guard let first = rest.first else { break }
            if first == "'" || first == "\"" {
                let body = rest.dropFirst()
                guard let close = body.firstIndex(of: first) else { break }
                words.append(String(body[..<close]))
                rest = body[body.index(after: close)...]
            } else {
                let end = rest.firstIndex { $0 == " " || $0 == "\t" } ?? rest.endIndex
                words.append(String(rest[..<end]))
                rest = rest[end...]
            }
        }
        return words
    }

    /// The path as one shell word: as is when it has only safe characters, else in single quotes.
    static func shellQuoted(_ path: String) -> String {
        let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789/._-+")
        if !path.isEmpty, path.unicodeScalars.allSatisfy(safe.contains) { return path }
        return "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

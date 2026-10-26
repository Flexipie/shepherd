import Foundation

/// `install claude` and `uninstall claude`: add or remove Shepherd's hooks in Claude Code's
/// settings. Shows the change as a diff first, asks before writing, and backs the file up. Runs
/// in tests with a temporary settings folder (`CLAUDE_CONFIG_DIR`).
public enum InstallCLI {
    public static let usage = """
        usage: install claude [--print] [--yes]
               uninstall claude [--print] [--yes]
        """

    /// `arguments` start with `install` or `uninstall`. `show` prints to stdout. `confirm` asks whether to write and returns nil when
    /// there is no one to ask (stdin is not a terminal).
    public static func run(arguments: [String], environment: [String: String],
                           show: (String) -> Void, confirm: () -> Bool?, now: Date = Date()) -> ReportCLI.Outcome {
        guard let verb = arguments.first, verb == "install" || verb == "uninstall" else {
            return .init(exitCode: 2, output: usage)
        }
        var agent: String?
        var printOnly = false, yes = false
        for argument in arguments.dropFirst() {
            switch argument {
            case "--print": printOnly = true
            case "--yes", "-y": yes = true
            case _ where argument.hasPrefix("-"): return .init(exitCode: 2, output: "unknown option \(argument)\n\(usage)")
            case _ where agent == nil: agent = argument
            default: return .init(exitCode: 2, output: "unexpected argument \(argument)\n\(usage)")
            }
        }
        guard let agent else { return .init(exitCode: 2, output: "name the agent: claude\n\(usage)") }
        guard agent == "claude" else {
            return .init(exitCode: 2, output: "\(agent) is not supported yet; only claude\n\(usage)")
        }

        let path = settingsURL(environment: environment)
        // A symlinked settings file (a dotfiles repo) is edited where it points, so the link stays.
        let target = path.resolvingSymlinksInPath()
        let exists = FileManager.default.fileExists(atPath: target.path)
        if !exists, let link = try? FileManager.default.destinationOfSymbolicLink(atPath: path.path) {
            return .init(exitCode: 1, output: "\(path.path) links to \(link), which is missing. Nothing written.")
        }
        let original: Data?
        let before: String
        let settings: SettingsJSON
        do {
            original = exists ? try Data(contentsOf: target) : nil
            before = original.map { String(decoding: $0, as: UTF8.self) } ?? ""
            settings = try SettingsJSON.parse(original ?? Data("{}".utf8))
        } catch {
            return .init(exitCode: 1, output: "cannot read \(path.path): \(error). Nothing written.")
        }

        let after: SettingsJSON
        do {
            after = verb == "install" ? try ClaudeHooks.install(into: settings)
                                      : try ClaudeHooks.uninstall(from: settings)
        } catch {
            return .init(exitCode: 1, output: "cannot change \(path.path): \(error). Nothing written.")
        }
        guard after != settings else {
            let state = verb == "install" ? "already installed in" : "not in"
            return .init(exitCode: 0, output: "Shepherd's hooks are \(state) \(path.path). Nothing to change.")
        }

        // The hooks run the bare name, so say so now if Claude Code will not find it.
        let warning = verb == "install" && !onPath(environment: environment)
            ? "\nshepherd-report is not on your PATH, so these hooks will fail until it is (link it into a folder on PATH)."
            : ""
        let text = after.printed()
        show(LineDiff.unified(from: before, to: text, oldName: path.path, newName: path.path))
        if printOnly { return .init(exitCode: 0, output: "--print: nothing written.\(warning)") }
        if !yes {
            guard let answer = confirm() else {
                return .init(exitCode: 1, output: "Nothing written. Run again with --yes to write this change.")
            }
            guard answer else { return .init(exitCode: 1, output: "Nothing written.") }
        }

        // Something else (Claude Code itself, an editor) may have saved the file while we asked.
        guard (try? Data(contentsOf: target)) == original else {
            return .init(exitCode: 1, output: "\(path.path) changed since the diff was shown. Nothing written; run again.")
        }
        do {
            var note = "no earlier file, so no backup"
            if exists {
                // Beside the link, not in the folder it points to (often a dotfiles repo).
                let backup = backupURL(for: path, now: now)
                try FileManager.default.copyItem(at: target, to: backup)
                note = "backup at \(backup.path)"
            } else {
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)
            }
            let permissions = try? FileManager.default.attributesOfItem(atPath: target.path)[.posixPermissions]
            try Data(text.utf8).write(to: target, options: .atomic)
            if let permissions {
                try? FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: target.path)
            }
            return .init(exitCode: 0, output: "Wrote \(path.path); \(note). Running Claude sessions pick it up when restarted.\(warning)")
        } catch {
            return .init(exitCode: 1, output: "cannot write \(path.path): \(error.localizedDescription)")
        }
    }

    /// `$CLAUDE_CONFIG_DIR/settings.json`, else `~/.claude/settings.json`: the user settings Claude
    /// Code reads.
    static func settingsURL(environment: [String: String]) -> URL {
        if let folder = environment["CLAUDE_CONFIG_DIR"], !folder.isEmpty {
            return URL(fileURLWithPath: folder).appending(path: "settings.json")
        }
        let home = environment["HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? NSHomeDirectory()
        return URL(fileURLWithPath: home).appending(path: ".claude/settings.json")
    }

    /// Whether an executable `shepherd-report` is in one of PATH's folders.
    static func onPath(environment: [String: String]) -> Bool {
        (environment["PATH"] ?? "").split(separator: ":").contains { folder in
            FileManager.default.isExecutableFile(atPath: "\(folder)/shepherd-report")
        }
    }

    /// `<file>.shepherd-backup-<yyyyMMdd-HHmmss>` beside the file, with a counter if that is taken.
    static func backupURL(for file: URL, now: Date) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let base = "\(file.lastPathComponent).shepherd-backup-\(formatter.string(from: now))"
        let folder = file.deletingLastPathComponent()
        var candidate = folder.appending(path: base)
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appending(path: "\(base)-\(counter)")
            counter += 1
        }
        return candidate
    }
}

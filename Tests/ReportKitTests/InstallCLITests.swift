import Foundation
import Testing
@testable import ReportKit

/// `install claude` writes a user's own settings file: these cover the edge (backup, only
/// Shepherd's entries touched, nothing written without a yes).
@Suite struct InstallCLITests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// A file as Claude Code writes it, with the user's own hooks, including one Shepherd must not
    /// mistake for its own.
    static let original = """
        {
          "model": "opus",
          "hooks": {
            "Stop": [
              {
                "hooks": [
                  {
                    "type": "command",
                    "command": "afplay /System/Library/Sounds/Glass.aiff",
                    "async": true
                  },
                  {
                    "type": "command",
                    "command": "echo shepherd-report report"
                  }
                ]
              }
            ],
            "PreToolUse": []
          },
          "statusLine": {
            "type": "command",
            "command": "~/bin/status \\"x\\" \\u001b",
            "padding": 0
          },
          "cleanupPeriodDays": 1.5e2
        }

        """

    final class Scratch {
        let url = FileManager.default.temporaryDirectory.appending(path: "install-cli-\(UUID().uuidString)")
        var settings: URL { url.appending(path: "claude/settings.json") }
        init(contents: String?) throws {
            try FileManager.default.createDirectory(at: url.appending(path: "claude"), withIntermediateDirectories: true)
            if let contents { try Data(contents.utf8).write(to: settings) }
        }
        func text() throws -> String { try String(contentsOf: settings, encoding: .utf8) }
        func backups() throws -> [URL] {
            try FileManager.default.contentsOfDirectory(at: settings.deletingLastPathComponent(), includingPropertiesForKeys: nil)
                .filter { $0.lastPathComponent.contains(".shepherd-backup-") }
        }
        deinit { try? FileManager.default.removeItem(at: url) }
    }

    func run(_ arguments: [String], _ scratch: Scratch, answer: Bool? = nil, path: String = "") -> (ReportCLI.Outcome, String) {
        var shown = ""
        let outcome = InstallCLI.run(arguments: arguments,
                                     environment: ["CLAUDE_CONFIG_DIR": scratch.url.appending(path: "claude").path, "PATH": path],
                                     binary: "/Apps/Shepherd.app/Contents/MacOS/shepherd-report",
                                     show: { shown += $0 }, confirm: { answer }, now: now)
        return (outcome, shown)
    }

    @Test func printShowsTheDiffAndWritesNothing() throws {
        let scratch = try Scratch(contents: Self.original)
        let (outcome, diff) = run(["install", "claude", "--print"], scratch)
        #expect(outcome.exitCode == 0)
        #expect(diff.contains("+            \"command\": \"shepherd-report report --status done --kind claude --from-hook\""))
        // A removed line only comes back with a comma, as an event before the new ones.
        let lines = diff.split(separator: "\n").dropFirst(2)
        for removed in lines where removed.hasPrefix("-") {
            #expect(lines.contains("+" + removed.dropFirst() + ","))
        }
        #expect(try scratch.text() == Self.original)
        #expect(try scratch.backups().isEmpty)
    }

    @Test(arguments: [nil, false] as [Bool?])
    func nothingIsWrittenWithoutAYes(_ answer: Bool?) throws {
        let scratch = try Scratch(contents: Self.original)
        let (outcome, diff) = run(["install", "claude"], scratch, answer: answer)
        #expect(outcome.exitCode == 1)
        #expect(!diff.isEmpty)
        #expect(try scratch.text() == Self.original)
        #expect(try scratch.backups().isEmpty)
    }

    @Test func installBacksUpAndUninstallRestoresTheFile() throws {
        let scratch = try Scratch(contents: Self.original)
        #expect(run(["install", "claude"], scratch, answer: true).0.exitCode == 0)
        let backups = try scratch.backups()
        #expect(backups.count == 1)
        #expect(try String(contentsOf: try #require(backups.first), encoding: .utf8) == Self.original)

        let installed = try SettingsJSON.parse(Data(try scratch.text().utf8))
        #expect(try ClaudeHooks.ours(in: installed).count == ClaudeHooks.entries.count)
        // The user's keys keep their order and values.
        guard case let .object(pairs) = installed else { Issue.record("not an object"); return }
        #expect(pairs.map(\.key) == ["model", "hooks", "statusLine", "cleanupPeriodDays"])
        #expect(installed["cleanupPeriodDays"] == .number("1.5e2"))

        let again = run(["install", "claude", "--yes"], scratch)
        #expect(again.0.exitCode == 0 && again.1.isEmpty)
        #expect(try scratch.backups().count == 1)

        #expect(run(["uninstall", "claude", "--yes"], scratch).0.exitCode == 0)
        #expect(try scratch.text() == Self.original)
        #expect(try scratch.backups().count == 2)
    }

    @Test func installReplacesAnOlderPathAndKeepsTheLink() throws {
        let scratch = try Scratch(contents: nil)
        let real = scratch.url.appending(path: "dotfiles-settings.json")
        // Hooks from a build that wrote the binary's quoted absolute path.
        let current = try ClaudeHooks.install(into: try SettingsJSON.parse(Data(Self.original.utf8))).printed()
        let old = current.replacingOccurrences(of: "\"shepherd-report report", with: "\"'/Old Place/shepherd-report' report")
        try Data(old.utf8).write(to: real)
        try FileManager.default.createSymbolicLink(at: scratch.settings, withDestinationURL: real)

        // Uninstall finds the older form too.
        #expect(run(["uninstall", "claude", "--yes"], scratch).0.exitCode == 0)
        #expect(try String(contentsOf: real, encoding: .utf8) == Self.original)
        try Data(old.utf8).write(to: real)

        #expect(run(["install", "claude", "--yes"], scratch).0.exitCode == 0)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: scratch.settings.path) == real.path)
        let commands = try ClaudeHooks.ours(in: try SettingsJSON.parse(Data(contentsOf: real))).map(\.2)
        #expect(commands.count == ClaudeHooks.entries.count)
        #expect(commands.allSatisfy { $0.hasPrefix("shepherd-report report ") })
    }

    @Test func aMissingFileIsCreatedWithoutABackup() throws {
        let scratch = try Scratch(contents: nil)
        #expect(run(["uninstall", "claude", "--yes"], scratch).0.exitCode == 0)
        #expect(!FileManager.default.fileExists(atPath: scratch.settings.path))
        #expect(run(["install", "claude", "--yes"], scratch).0.exitCode == 0)
        #expect(try ClaudeHooks.ours(in: try SettingsJSON.parse(Data(scratch.text().utf8))).count == ClaudeHooks.entries.count)
        #expect(try scratch.backups().isEmpty)
    }

    @Test(arguments: [#"{"hooks": {,}"#, "// mine\n{}", "[]", #"{"hooks": []}"#, #"{"hooks": {"Stop": {}}}"#,
                       #"{"hooks": {}, "hooks": {"Stop": []}}"#])
    func aFileItCannotEditIsLeftAlone(_ contents: String) throws {
        let scratch = try Scratch(contents: contents)
        let (outcome, diff) = run(["install", "claude", "--yes"], scratch)
        #expect(outcome.exitCode == 1)
        #expect(diff.isEmpty)
        #expect(try scratch.text() == contents)
        #expect(try scratch.backups().isEmpty)
    }

    @Test func aLinkToAMissingFileIsLeftALink() throws {
        let scratch = try Scratch(contents: nil)
        let missing = scratch.url.appending(path: "not-cloned/settings.json")
        try FileManager.default.createSymbolicLink(at: scratch.settings, withDestinationURL: missing)
        #expect(run(["install", "claude", "--yes"], scratch).0.exitCode == 1)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: scratch.settings.path) == missing.path)
        #expect(!FileManager.default.fileExists(atPath: missing.path))
    }

    @Test func aChangeWhileAskingIsNotOverwritten() throws {
        let scratch = try Scratch(contents: Self.original)
        let edited = Self.original.replacingOccurrences(of: "opus", with: "sonnet")
        var shown = ""
        let outcome = InstallCLI.run(arguments: ["install", "claude"],
                                     environment: ["CLAUDE_CONFIG_DIR": scratch.url.appending(path: "claude").path], binary: nil,
                                     show: { shown += $0 },
                                     confirm: { try? Data(edited.utf8).write(to: scratch.settings); return true }, now: now)
        #expect(outcome.exitCode == 1)
        #expect(try scratch.text() == edited)
        #expect(try scratch.backups().isEmpty)
    }

    @Test func installWarnsBeforeAskingWhenTheCommandIsNotOnPath() throws {
        let scratch = try Scratch(contents: Self.original)
        let bin = scratch.url.appending(path: "bin")
        try FileManager.default.createDirectory(at: bin.appending(path: "shepherd-report"), withIntermediateDirectories: true)
        var shownWhenAsked = ""
        var shown = ""
        let outcome = InstallCLI.run(arguments: ["install", "claude"],
                                     environment: ["CLAUDE_CONFIG_DIR": scratch.url.appending(path: "claude").path, "PATH": bin.path],
                                     binary: "/Apps/Shepherd.app/Contents/MacOS/shepherd-report",
                                     show: { shown += $0 }, confirm: { shownWhenAsked = shown; return true }, now: now)
        #expect(outcome.exitCode == 0)
        #expect(shownWhenAsked.contains("not on this shell's PATH"))
        // The only folder on PATH already holds a shepherd-report, so the link goes to /usr/local/bin.
        #expect(shownWhenAsked.contains("sudo mkdir -p /usr/local/bin && sudo ln -s '/Apps/Shepherd.app/Contents/MacOS/shepherd-report' /usr/local/bin/shepherd-report"))
        // Installing again still says so; uninstalling never does.
        #expect(run(["install", "claude", "--yes"], scratch, path: bin.path).0.output.contains("not on this shell's PATH"))
        let removed = run(["uninstall", "claude", "--yes"], scratch, path: bin.path)
        #expect(!removed.0.output.contains("PATH") && !removed.1.contains("PATH"))
    }

    @Test func theLinkGoesToAFolderOnPathTheUserCanWrite() throws {
        let scratch = try Scratch(contents: Self.original)
        let bin = scratch.url.appending(path: "my bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let (outcome, shown) = run(["install", "claude", "--print"], scratch, path: "relative:/usr/bin:\(bin.path)")
        #expect(outcome.exitCode == 0)
        #expect(shown.contains("  ln -s '/Apps/Shepherd.app/Contents/MacOS/shepherd-report' '\(bin.path)/shepherd-report'\n"))
        #expect(InstallCLI.shellQuoted("/Sam's Apps/x") == #"'/Sam'\''s Apps/x'"#)
    }

    @Test func noWarningWhenTheCommandIsOnPath() throws {
        let scratch = try Scratch(contents: Self.original)
        let bin = scratch.url.appending(path: "bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let tool = bin.appending(path: "shepherd-report")
        try Data("#!/bin/sh\n".utf8).write(to: tool)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
        let (outcome, shown) = run(["install", "claude", "--print"], scratch, path: "/nowhere:\(bin.path)")
        #expect(!outcome.output.contains("PATH") && !shown.contains("PATH"))
    }

    @Test(arguments: [["install"], ["install", "codex"], ["install", "claude", "--force"], ["remove", "claude"]])
    func badUsageExitsTwo(_ arguments: [String]) throws {
        let scratch = try Scratch(contents: Self.original)
        #expect(run(arguments, scratch, answer: true).0.exitCode == 2)
        #expect(try scratch.text() == Self.original)
    }

    @Test(arguments: [
        ("/a/shepherd-report report --status done", true),
        ("'/My Apps/shepherd-report' report --status idle", true),
        ("shepherd report --status working", true),
        ("echo shepherd-report report", false),
        ("/a/shepherd-report-old report", false),
        ("shepherd-report install claude", false),
    ])
    func onlyShepherdsReportCommandsAreOurs(_ command: String, _ ours: Bool) {
        #expect(ClaudeHooks.isOurs(.object([(key: "type", value: .string("command")), (key: "command", value: .string(command))])) == ours)
    }
}

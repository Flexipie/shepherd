import Foundation
import Testing
@testable import ReportSource

/// Claude Code's settings are only read, and leniently: anything Shepherd cannot use means no hooks.
@Suite struct ClaudeSetupTests {
    let folder = FileManager.default.temporaryDirectory.appending(path: "claude-setup-\(UUID().uuidString)")

    func detect(_ settings: String?) throws -> ClaudeSetup {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        if let settings { try Data(settings.utf8).write(to: folder.appending(path: "settings.json")) }
        return ClaudeSetup.detect(environment: ["CLAUDE_CONFIG_DIR": folder.path])
    }

    @Test func noFolderIsNotFound() {
        #expect(ClaudeSetup.detect(environment: ["CLAUDE_CONFIG_DIR": folder.path]) == .notFound)
    }

    @Test func missingOddOrBrokenSettingsHaveNoHooks() throws {
        #expect(try detect(nil) == .noHooks)
        #expect(try detect("not json") == .noHooks)
        #expect(try detect(#"{"hooks": ["not", "an", "object"], "unknown": 1}"#) == .noHooks)
        #expect(try detect(#"{"hooks": {"Stop": [{"hooks": [{"type": "command", "command": "other-tool report"}]}]}}"#) == .noHooks)
    }

    @Test func shepherdsHookIsFound() throws {
        let settings = #"{"model": "x", "hooks": {"Stop": [{"hooks": [{"type": "command", "command": "shepherd-report report --status done --kind claude --from-hook"}], "extra": true}]}}"#
        #expect(try detect(settings) == .hooksInstalled)
    }
}

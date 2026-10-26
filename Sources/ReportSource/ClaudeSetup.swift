import Foundation
import ReportKit

/// Whether Claude Code is on this Mac and reports to Shepherd. Reads only: its settings folder and
/// file are looked at, never written.
public enum ClaudeSetup: Sendable, Equatable {
    /// Claude Code's settings folder is missing.
    case notFound
    /// Claude Code is here, but its settings run none of Shepherd's hooks.
    case noHooks
    /// Claude Code runs Shepherd's hooks, so it reports its own status.
    case hooksInstalled

    /// `$CLAUDE_CONFIG_DIR`, else `~/.claude`, and the `settings.json` in it. A file that cannot
    /// be read or parsed has no hooks.
    public static func detect(environment: [String: String]) -> ClaudeSetup {
        let settings = InstallCLI.settingsURL(environment: environment)
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: settings.deletingLastPathComponent().path, isDirectory: &isFolder),
              isFolder.boolValue else { return .notFound }
        guard let data = try? Data(contentsOf: settings.resolvingSymlinksInPath()),
              let parsed = try? SettingsJSON.parse(data) else { return .noHooks }
        return ClaudeHooks.isInstalled(in: parsed) ? .hooksInstalled : .noHooks
    }
}

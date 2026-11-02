import Testing
@testable import ReportSource

@Suite struct ClaudeSetupTests {
    /// The first-run card's command names the binary by its full path: the one inside the app is not
    /// on PATH, so a bare `shepherd-report` pasted into a fresh terminal is not found (#105).
    @Test func theInstallCommandNamesTheBinaryByItsFullPath() {
        #expect(ClaudeSetup.installCommand(binary: "/Applications/Shepherd.app/Contents/MacOS/shepherd-report")
            == "'/Applications/Shepherd.app/Contents/MacOS/shepherd-report' install claude")
    }
}

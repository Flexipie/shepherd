import Foundation
import Testing
@testable import ReportKit

@Suite struct ReportCLITests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    final class Scratch {
        let url = FileManager.default.temporaryDirectory.appending(path: "report-cli-\(UUID().uuidString)")
        deinit { try? FileManager.default.removeItem(at: url) }
    }

    func run(_ arguments: [String], spool: URL, stdin: String = "", cwd: String = "/work/app",
             environment: [String: String] = [:]) -> ReportCLI.Outcome {
        var env = environment
        env["SHEPHERD_SPOOL_DIR"] = spool.path
        return ReportCLI.run(arguments: ["report"] + arguments, stdin: { Data(stdin.utf8) }, environment: env,
                             cwd: cwd, now: now)
    }

    @Test(arguments: [
        [],
        ["--status", "working", "extra"],
        ["--message", "hi"],
        ["--status"],
        ["--status", "napping"],
        ["--status", "working", "--bogus", "x"],
        ["--status", "working", "--from-hook=yes"],
    ])
    func badUsageExitsTwo(_ arguments: [String]) {
        let scratch = Scratch()
        let outcome = run(arguments, spool: scratch.url)
        #expect(outcome.exitCode == 2)
        #expect(!outcome.output.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: scratch.url.path))
    }

    @Test func aMissingSubcommandExitsTwo() {
        let scratch = Scratch()
        let outcome = ReportCLI.run(arguments: ["status", "--status", "working"], stdin: { Data() },
                                    environment: ["SHEPHERD_SPOOL_DIR": scratch.url.path], cwd: "/w", now: now)
        #expect(outcome.exitCode == 2)
    }

    @Test(arguments: ["working", "blocked", "done", "idle"])
    func eachStatusIsWrittenForTheFolder(_ status: String) throws {
        let scratch = Scratch()
        let outcome = run(["--status", status, "--message", "  hello  ", "--kind=claude"], spool: scratch.url)
        #expect(outcome == ReportCLI.Outcome(exitCode: 0, output: ""))
        let report = try #require(try ReportSpool(directory: scratch.url).read().reports.first)
        #expect(report.agent == "cwd:/work/app")
        #expect(report.status.rawValue == status)
        #expect(report.message == "hello")
        #expect(report.kind == "claude")
        #expect(report.cwd == "/work/app")
        #expect(report.updatedAt == now)
    }

    @Test func closedRemovesTheReport() throws {
        let scratch = Scratch()
        #expect(run(["--status", "working", "--agent", "demo"], spool: scratch.url).exitCode == 0)
        #expect(try ReportSpool(directory: scratch.url).read().reports.count == 1)
        #expect(run(["--status", "closed", "--agent", "demo"], spool: scratch.url).exitCode == 0)
        #expect(try ReportSpool(directory: scratch.url).read().reports.isEmpty)
        #expect(run(["--status", "closed", "--agent", "demo"], spool: scratch.url).exitCode == 0)
    }

    @Test func aTmuxPaneNamesTheAgent() throws {
        let scratch = Scratch()
        let env = ["TMUX": "/tmp/tmux-501/default,88,0", "TMUX_PANE": "%4"]
        #expect(run(["--status", "done"], spool: scratch.url, environment: env).exitCode == 0)
        let report = try #require(try ReportSpool(directory: scratch.url).read().reports.first)
        #expect(report.agent == "tmux:/tmp/tmux-501/default:%4")
    }

    @Test func aNotificationHookSuppliesTheSessionFolderAndMessage() throws {
        let scratch = Scratch()
        let json = #"{"session_id": "s-9", "cwd": "/hooked", "message": "Claude needs your permission", "hook_event_name": "Notification"}"#
        let outcome = run(["--status", "blocked", "--from-hook"], spool: scratch.url, stdin: json, cwd: "/elsewhere")
        #expect(outcome.exitCode == 0)
        let report = try #require(try ReportSpool(directory: scratch.url).read().reports.first)
        #expect(report.agent == "session:s-9")
        #expect(report.cwd == "/hooked")
        #expect(report.message == "Claude needs your permission")
    }

    @Test func aStopHookUsesTheLastReplyAndAFlagMessageWins() throws {
        let scratch = Scratch()
        let stop = #"{"session_id": "s-1", "last_assistant_message": "Done with the refactor"}"#
        #expect(run(["--status", "done", "--from-hook"], spool: scratch.url, stdin: stop).exitCode == 0)
        #expect(try ReportSpool(directory: scratch.url).read().reports.first?.message == "Done with the refactor")
        #expect(run(["--status", "done", "--from-hook", "--message", "Mine"], spool: scratch.url, stdin: stop).exitCode == 0)
        #expect(try ReportSpool(directory: scratch.url).read().reports.first?.message == "Mine")
    }

    @Test func hookInputThatIsNotAnObjectExitsTwo() {
        let scratch = Scratch()
        let outcome = run(["--status", "done", "--from-hook"], spool: scratch.url, stdin: "[1, 2")
        #expect(outcome.exitCode == 2)
        #expect(!FileManager.default.fileExists(atPath: scratch.url.path))
    }

    @Test func aLongMessageIsCappedNotRejected() throws {
        let scratch = Scratch()
        let long = String(repeating: "a", count: 9000)
        #expect(run(["--status", "working", "--message", long], spool: scratch.url).exitCode == 0)
        let report = try #require(try ReportSpool(directory: scratch.url).read().reports.first)
        #expect(report.message?.utf8.count == ReportFile.messageLimit)
    }

    @Test func aSpoolThatCannotBeWrittenExitsOne() throws {
        let scratch = Scratch()
        // A file where the folder should be: the folder cannot be created.
        try Data().write(to: scratch.url)
        let outcome = run(["--status", "working"], spool: scratch.url)
        #expect(outcome.exitCode == 1)
        #expect(outcome.output.contains(scratch.url.path))
    }
}

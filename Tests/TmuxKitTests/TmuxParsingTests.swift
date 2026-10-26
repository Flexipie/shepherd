import Darwin
import Foundation
import Testing
@testable import TmuxKit

@Suite struct TmuxParsingTests {
    @Test func aPaneLineParsesEveryField() throws {
        let line = ["w", "@2", "1", "%7", "4242", "1", "1", "claude.exe", "/work/app"].joined(separator: "\t")
        let pane = try #require(TmuxPane.parse(line, socket: "/tmp/s"))
        #expect(pane == TmuxPane(socket: "/tmp/s", session: "w", windowID: "@2", windowIndex: 1, paneID: "%7", pid: 4242,
                                 isActive: true, command: "claude.exe", path: "/work/app"))
    }

    @Test func aPathWithATabKeepsItsTab() throws {
        let line = ["w", "@0", "0", "%0", "1", "1", "1", "zsh", "/work/a\tb"].joined(separator: "\t")
        #expect(try #require(TmuxPane.parse(line, socket: "s")).path == "/work/a\tb")
    }

    @Test func aPaneIsActiveOnlyWhenItsWindowAndItAreActive() throws {
        let inactiveWindow = ["w", "@0", "0", "%0", "1", "0", "1", "zsh", "/"].joined(separator: "\t")
        let inactivePane = ["w", "@0", "0", "%0", "1", "1", "0", "zsh", "/"].joined(separator: "\t")
        #expect(try #require(TmuxPane.parse(inactiveWindow, socket: "s")).isActive == false)
        #expect(try #require(TmuxPane.parse(inactivePane, socket: "s")).isActive == false)
    }

    @Test func aMalformedPaneLineIsSkipped() {
        #expect(TmuxPane.parse("w\t@0\tnot-a-number", socket: "s") == nil)
        #expect(TmuxPane.parse("", socket: "s") == nil)
    }

    @Test func clientLinesSayWhetherTheyAreControlClients() throws {
        let terminal = try #require(TmuxAttachedClient.parse("1234\tw\t0"))
        #expect(terminal == TmuxAttachedClient(pid: 1234, session: "w", isControl: false))
        #expect(try #require(TmuxAttachedClient.parse("99\tw\t1")).isControl)
        #expect(TmuxAttachedClient.parse("x\tw\t0") == nil)
    }

    @Test func surfaceKeyNamesBecomeTmuxNames() {
        #expect(TmuxKeys.name("enter") == "Enter")
        #expect(TmuxKeys.name("escape") == "Escape")
        #expect(TmuxKeys.name("esc") == "Escape")
        #expect(TmuxKeys.name("up") == "Up")
        #expect(TmuxKeys.name("1") == "1")
        #expect(TmuxKeys.name("C-c") == "C-c")
    }

    @Test func theSocketDirectoryFollowsTmuxTmpdir() {
        #expect(TmuxSockets.directory(environment: ["TMUX_TMPDIR": "/var/x"]).path.hasPrefix("/var/x/tmux-"))
        #expect(TmuxSockets.directory(environment: [:]).path.hasPrefix("/tmp/tmux-"))
    }
}

@Suite struct ControlEventTests {
    @Test func outputNamesThePane() {
        #expect(ControlEvent.parse("%output %3 hello\\015\\012") == .output(pane: "%3"))
        #expect(ControlEvent.parse("%extended-output %4 12 : text") == .output(pane: "%4"))
    }

    @Test func structureChangesAreLayoutAndTheEndIsExit() {
        #expect(ControlEvent.parse("%window-add @5") == .layout)
        #expect(ControlEvent.parse("%session-changed $0 w") == .layout)
        #expect(ControlEvent.parse("%layout-change @1 abc") == .layout)
        #expect(ControlEvent.parse("%exit") == .exit)
        #expect(ControlEvent.parse("%exit detached") == .exit)
    }

    @Test func replyBlocksAndPlainLinesAreOther() {
        #expect(ControlEvent.parse("%begin 1 2 0") == .other)
        #expect(ControlEvent.parse("%end 1 2 0") == .other)
        #expect(ControlEvent.parse("just some text") == .other)
        #expect(ControlEvent.parse("%output") == .other)
    }
}

@Suite struct ProcessTableTests {
    static let ps = """
      100     1 /sbin/launchd
      200   100 /bin/zsh -l
      300   200 /Users/x/.npm/bin/claude.exe daemon run
      301   300 /bin/sh /work/tools/codex
      400   100 /usr/bin/node /opt/agent/cli.js
      401   400 /usr/bin/python3 -m tool
    """

    @Test func parsesThePsColumns() {
        let table = ProcessTable.parse(Self.ps)
        #expect(table.names(under: 100).first == "launchd")
        #expect(table.names(under: 200) == ["zsh", "claude", "codex"])
    }

    @Test func aDescendantIsFoundUnderItsShell() {
        let table = ProcessTable.parse(Self.ps)
        #expect(table.names(under: 200).contains("claude"))
        #expect(table.names(under: 200).contains("codex"))
        #expect(!table.names(under: 100).isEmpty)
    }

    @Test func aScriptRunByAnInterpreterIsNamedByTheScript() {
        #expect(ProcessTable.name(of: "/bin/sh /work/tools/codex") == "codex")
        #expect(ProcessTable.name(of: "/usr/bin/node /opt/agent/cli.js") == "cli.js")
        #expect(ProcessTable.name(of: "/Users/x/bin/claude.exe --resume") == "claude")
    }

    @Test func aProcessIsNotItsOwnParent() {
        let table = ProcessTable.parse("5 5 /loop\n")
        #expect(table.names(under: 5) == ["loop"])
    }

    @Test func aSnapshotOfTheMachineHasItsOwnPids() {
        let table = ProcessTable.snapshot()
        #expect(table.names(under: getpid()).contains { !$0.isEmpty })
    }
}

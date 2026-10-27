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

    /// A session tmux closes once unattached must never be held open by Shepherd's control client.
    @Test func destroyUnattachedSaysWhetherTheSessionClosesUnattached() throws {
        func closes(_ value: String, grouped: Bool = false, size: Int = 0) throws -> Bool {
            let line = ["100", value, grouped ? "1" : "0", grouped ? "\(size)" : "", "0", "$3", "work"].joined(separator: "\t")
            return try #require(TmuxSession.parse(line)).closesWhenUnattached
        }
        #expect(try closes("off") == false)
        #expect(try closes("") == true)
        #expect(try closes("on") == true)
        #expect(try closes("on", grouped: true, size: 2) == true)
        #expect(try closes("keep-last") == false)
        #expect(try closes("keep-last", grouped: true, size: 1) == false)
        #expect(try closes("keep-last", grouped: true, size: 2) == true)
        #expect(try closes("keep-group") == true)
        #expect(try closes("keep-group", grouped: true, size: 1) == false)
        #expect(try closes("keep-group", grouped: true, size: 2) == true)
        #expect(try closes("something-new") == true)
        // `exit-unattached`: the whole server exits once no client is left.
        let exits = ["100", "off", "0", "", "1", "$3", "work"].joined(separator: "\t")
        #expect(try #require(TmuxSession.parse(exits)).closesWhenUnattached)
    }

    @Test func clientLinesSayWhetherTheyAreControlClients() throws {
        let terminal = try #require(TmuxAttachedClient.parse("1234\t0\t1700000000\t/dev/ttys003\tw"))
        #expect(terminal == TmuxAttachedClient(pid: 1234, session: "w", isControl: false, name: "/dev/ttys003",
                                               activity: 1_700_000_000))
        #expect(try #require(TmuxAttachedClient.parse("99\t1\t0\tclient-99\tw")).isControl)
        // A session name with a tab stays whole.
        #expect(try #require(TmuxAttachedClient.parse("1\t0\t0\t/dev/ttys1\ta\tb")).session == "a\tb")
        #expect(TmuxAttachedClient.parse("x\t0\t0\t/dev/ttys1\tw") == nil)
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

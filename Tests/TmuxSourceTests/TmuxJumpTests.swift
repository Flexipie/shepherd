import Darwin
import Testing
@testable import TmuxKit
@testable import TmuxSource

/// Which terminal a jump uses: switching the wrong one changes what the user is looking at.
@Suite struct TmuxJumpTests {
    func client(_ pid: pid_t, on session: String, activity: Int, control: Bool = false) -> TmuxAttachedClient {
        TmuxAttachedClient(pid: pid, session: session, isControl: control, name: "/dev/ttys\(pid)", activity: activity)
    }

    func session(_ name: String, closes: Bool = false) -> TmuxSession {
        TmuxSession(id: "$" + name, name: name, activity: 0, closesWhenUnattached: closes)
    }

    func outcome(_ clients: [TmuxAttachedClient], sessions: [TmuxSession] = [], own: pid_t? = nil,
                 remote: Set<pid_t> = []) -> TmuxJump.Outcome {
        TmuxJump.outcome(session: "agent", clients: clients, sessions: sessions, own: own,
                         isLocal: { !remote.contains($0.pid) })
    }

    @Test func aTerminalOnTheAgentsSessionIsUsedAsItIs() {
        let clients = [client(1, on: "agent", activity: 10), client(2, on: "b", activity: 50)]
        #expect(outcome(clients) == .show(.init(client: clients[0], switches: false)))
    }

    @Test func otherwiseTheMostRecentlyActiveTerminalIsSwitched() {
        let clients = [client(1, on: "a", activity: 10), client(2, on: "b", activity: 50), client(3, on: "c", activity: 20)]
        #expect(outcome(clients) == .show(.init(client: clients[1], switches: true)))
    }

    @Test func shepherdsOwnControlClientIsNeverATerminal() {
        let own = client(9, on: "agent", activity: 99, control: true)
        #expect(outcome([own], own: 9) == .noTerminal)
        // Not known yet: every control client is taken for Shepherd's.
        #expect(outcome([own]) == .noTerminal)
        // iTerm2's `tmux -CC` is a terminal.
        let iterm = client(4, on: "b", activity: 5, control: true)
        #expect(outcome([own, iterm], own: 9) == .show(.init(client: iterm, switches: true)))
    }

    @Test func aTerminalOverSSHIsNeverSwitched() {
        let phone = client(1, on: "b", activity: 50)
        let mac = client(2, on: "c", activity: 10)
        #expect(outcome([phone, mac], remote: [1]) == .show(.init(client: mac, switches: true)))
        #expect(outcome([phone], remote: [1]) == .noTerminal)
        // One with no app found above it that already shows the agent (inside a herdr pane) is used,
        // and nothing else moves.
        let inHerdr = client(3, on: "agent", activity: 1)
        #expect(outcome([inHerdr, mac], remote: [3]) == .show(.init(client: inHerdr, switches: false)))
    }

    @Test func aTerminalIsNotSwitchedAwayFromASessionThatWouldClose() {
        let latest = client(1, on: "a", activity: 50)
        let older = client(2, on: "b", activity: 10)
        let sessions = [session("a", closes: true), session("b")]
        #expect(outcome([latest, older], sessions: sessions) == .show(.init(client: older, switches: true)))
        #expect(outcome([latest], sessions: sessions) == .wouldClose("a"))
        // Another client keeps the session open, so it can move.
        let other = client(3, on: "a", activity: 5)
        #expect(outcome([latest, other], sessions: sessions, remote: [3]) == .show(.init(client: latest, switches: true)))
    }
}

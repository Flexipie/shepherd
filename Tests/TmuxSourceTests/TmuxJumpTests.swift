import Darwin
import Testing
@testable import TmuxKit
@testable import TmuxSource

/// Which terminal a jump uses: switching the wrong one changes what the user is looking at.
@Suite struct TmuxJumpTests {
    func client(_ pid: pid_t, on session: String, activity: Int, control: Bool = false) -> TmuxAttachedClient {
        TmuxAttachedClient(pid: pid, session: session, isControl: control, name: "/dev/ttys\(pid)", activity: activity)
    }

    @Test func aTerminalOnTheAgentsSessionIsUsedAsItIs() {
        let clients = [client(1, on: "a", activity: 10), client(2, on: "b", activity: 50)]
        #expect(TmuxJump.target(session: "a", clients: clients, own: nil) == .init(client: clients[0], switches: false))
    }

    @Test func otherwiseTheMostRecentlyActiveTerminalIsSwitched() {
        let clients = [client(1, on: "a", activity: 10), client(2, on: "b", activity: 50), client(3, on: "c", activity: 20)]
        #expect(TmuxJump.target(session: "agent", clients: clients, own: nil) == .init(client: clients[1], switches: true))
    }

    @Test func shepherdsOwnControlClientIsNeverATerminal() {
        let own = client(9, on: "agent", activity: 99, control: true)
        #expect(TmuxJump.target(session: "agent", clients: [own], own: 9) == nil)
        // Not known yet: every control client is taken for Shepherd's.
        #expect(TmuxJump.target(session: "agent", clients: [own], own: nil) == nil)
        // iTerm2's `tmux -CC` is a terminal.
        let iterm = client(4, on: "b", activity: 5, control: true)
        #expect(TmuxJump.target(session: "agent", clients: [own, iterm], own: 9) == .init(client: iterm, switches: true))
    }
}

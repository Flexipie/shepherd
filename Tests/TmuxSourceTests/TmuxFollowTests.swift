import Testing
@testable import TmuxKit
@testable import TmuxSource

/// Where Shepherd's control client sits decides where a plain `tmux attach` lands and whether a
/// session tmux would close stays open, so the choice is checked against what tmux does alone.
@Suite struct TmuxFollowTests {
    /// Least recently used first, as `TmuxClient.sessions` lists them.
    func session(_ name: String, closes: Bool = false) -> TmuxSession {
        TmuxSession(id: "$" + name, name: name, activity: 0, closesWhenUnattached: closes)
    }

    func terminal(on session: String) -> TmuxAttachedClient {
        TmuxAttachedClient(pid: 1, session: session, isControl: false)
    }

    @Test func itSitsWithATerminalSoDetachedSessionsStayDetached() {
        let sessions = [session("a"), session("b"), session("c")]
        let choice = TmuxFollow.choose(sessions: sessions, terminals: [terminal(on: "a"), terminal(on: "b")], current: nil)
        #expect(choice == .init(session: "$b", parked: false))
    }

    @Test func withNoTerminalItParksOnTheLeastRecentlyUsedAndStays() {
        let sessions = [session("a"), session("b")]
        let parked = TmuxFollow.choose(sessions: sessions, terminals: [], current: nil)
        #expect(parked == .init(session: "$a", parked: true))
        // Attaching made `a` the most recent; the client stays rather than chase the least recent.
        #expect(TmuxFollow.choose(sessions: [session("b"), session("a")], terminals: [], current: parked) == parked)
    }

    @Test func whenItsTerminalLeavesItMovesOffTheUsersLatestSession() {
        let current = TmuxFollow.Choice(session: "$b", parked: false)
        #expect(TmuxFollow.choose(sessions: [session("a"), session("b")], terminals: [], current: current)
            == .init(session: "$a", parked: true))
    }

    @Test func aSessionTmuxClosesUnattachedIsNeverHeldWithoutATerminal() {
        let sessions = [session("a", closes: true), session("b")]
        #expect(TmuxFollow.choose(sessions: sessions, terminals: [], current: nil) == .init(session: "$b", parked: true))
        #expect(TmuxFollow.choose(sessions: [session("a", closes: true)], terminals: [], current: nil) == nil)
        let onA = TmuxFollow.Choice(session: "$a", parked: false)
        #expect(TmuxFollow.choose(sessions: sessions, terminals: [], current: onA) == .init(session: "$b", parked: true))
    }
}

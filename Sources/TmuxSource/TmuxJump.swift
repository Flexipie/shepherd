import Darwin
import TmuxKit

/// Which terminal a jump shows an agent in. A terminal already on the agent's session shows it as
/// it is; otherwise the most recently active terminal is switched to the agent, since selecting a
/// pane in a session nobody looks at shows nothing. Any client already on the session counts, even
/// one with no app found above it (inside a herdr pane, say). Only a terminal running in an app on
/// this Mac is switched (one over ssh would change a screen the user is not looking at), Shepherd's
/// own control client never is, and none is switched away from a session that would then close.
enum TmuxJump {
    struct Target: Equatable {
        let client: TmuxAttachedClient
        /// It is on another session, so it must be switched to the agent first.
        let switches: Bool
    }

    enum Outcome: Equatable {
        case show(Target)
        /// No client is on the agent's session and no terminal on this Mac is attached to the server.
        case noTerminal
        /// Every terminal that could be switched is the last one on a session tmux closes once
        /// unattached (`TmuxSession.closesWhenUnattached`), named here.
        case wouldClose(String)
    }

    /// `own` is Shepherd's control client on the server; while that is not known yet, every control
    /// client is taken for Shepherd's. `isLocal` says whether a client runs in an app on this Mac. A
    /// target that is not local shows the agent already, with no app to bring forward.
    static func outcome(session: String?, clients: [TmuxAttachedClient], sessions: [TmuxSession], own: pid_t?,
                        isLocal: (TmuxAttachedClient) -> Bool) -> Outcome {
        // Another control-mode client (iTerm2's `tmux -CC`) is a terminal too.
        let attached = clients.filter { !$0.isControl || (own != nil && $0.pid != own) }
        let latest: ([TmuxAttachedClient]) -> TmuxAttachedClient? = { $0.max { $0.activity < $1.activity } }
        let onSession = attached.filter { $0.session == session }
        if let shown = latest(onSession.filter(isLocal)) ?? latest(onSession) {
            return .show(Target(client: shown, switches: false))
        }
        let terminals = attached.filter(isLocal)
        guard !terminals.isEmpty else { return .noTerminal }
        let closing = Set(sessions.filter(\.closesWhenUnattached).map(\.name))
        let movable = terminals.filter { terminal in
            !closing.contains(terminal.session) || attached.contains { $0 != terminal && $0.session == terminal.session }
        }
        guard let client = latest(movable) else { return .wouldClose(latest(terminals)?.session ?? "") }
        return .show(Target(client: client, switches: true))
    }
}

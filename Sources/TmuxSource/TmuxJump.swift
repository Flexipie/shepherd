import Darwin
import TmuxKit

/// Which terminal a jump shows an agent in. A terminal already on the agent's session shows it as
/// it is; otherwise the most recently active terminal is switched to the agent, since selecting a
/// pane in a session nobody looks at shows nothing. Shepherd's own control client is never one.
enum TmuxJump {
    struct Target: Equatable {
        let client: TmuxAttachedClient
        /// It is on another session, so it must be switched to the agent first.
        let switches: Bool
    }

    /// Nil when no terminal is attached to the server. `own` is Shepherd's control client on it;
    /// while that is not known yet, every control client is taken for Shepherd's.
    static func target(session: String?, clients: [TmuxAttachedClient], own: pid_t?) -> Target? {
        // Another control-mode client (iTerm2's `tmux -CC`) is a terminal too.
        let terminals = clients.filter { !$0.isControl || (own != nil && $0.pid != own) }
        let latest: ([TmuxAttachedClient]) -> TmuxAttachedClient? = { $0.max { $0.activity < $1.activity } }
        if let onSession = latest(terminals.filter { $0.session == session }) {
            return Target(client: onSession, switches: false)
        }
        return latest(terminals).map { Target(client: $0, switches: true) }
    }
}

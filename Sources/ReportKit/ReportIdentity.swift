import Foundation

/// Which agent a report is about. The first of these that applies wins: the `--agent` flag, the
/// `SHEPHERD_AGENT_ID` variable, the tmux pane, the hook's session, the working directory. The
/// last two are weak: two agents in one folder share a key, and two sessions in one folder with no
/// hook share a row.
public struct ReportIdentity: Sendable, Equatable {
    public enum Method: String, Sendable, Equatable {
        case flag, environment, tmux, session, directory
    }

    public let key: String
    public let method: Method

    /// `session` is the hook's session id, and only given when the report came from a hook.
    public static func resolve(agent: String?, session: String?, cwd: String,
                               environment: [String: String]) -> ReportIdentity {
        if let agent = nonEmpty(agent) {
            return ReportIdentity(key: agent, method: .flag)
        }
        if let id = nonEmpty(environment["SHEPHERD_AGENT_ID"]) {
            return ReportIdentity(key: id, method: .environment)
        }
        // TMUX is "<socket path>,<server pid>,<session index>"; tmux's own #{socket_path} is the first part.
        if let tmux = nonEmpty(environment["TMUX"]), let pane = nonEmpty(environment["TMUX_PANE"]),
           let socket = tmux.split(separator: ",", maxSplits: 1).first {
            return ReportIdentity(key: "tmux:\(socket):\(pane)", method: .tmux)
        }
        if let session = nonEmpty(session) {
            return ReportIdentity(key: "session:\(session)", method: .session)
        }
        return ReportIdentity(key: "cwd:\(cwd)", method: .directory)
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}

import Foundation
import HerdrKit

/// Reading and typing into agents. Answering a blocked agent (a digit or Return) sets it working
/// and Escape sets it idle, which is roughly what a real agent does after an approval prompt.
extension FakeHerdrServer {
    static let keyNames: Set<String> = ["enter", "return", "esc", "escape", "tab", "up", "down", "left", "right", "backspace", "space"]

    func serveInput(_ method: String, _ params: [String: Any], _ connection: LineConnection, _ requestID: String) {
        let target = params["target"] as? String ?? params["pane_id"] as? String ?? ""
        guard let pane = herd.panes.first(where: { $0.id == target }) else {
            let code = method == "pane.send_input" ? "pane_not_found" : "agent_not_found"
            return replyError(connection, requestID, code: code, message: "\(target) not found")
        }
        switch method {
        case "agent.read":
            let text = screens[target] ?? FakeScreens.screen(kind: pane.agent, status: pane.status)
            let lines = (params["lines"] as? Int).map { text.split(separator: "\n", omittingEmptySubsequences: false).suffix($0) }
            let read: [String: Any] = [
                "pane_id": target, "workspace_id": pane.workspaceID, "tab_id": "\(pane.workspaceID):t1",
                "source": params["source"] as? String ?? "visible", "format": "text",
                "text": lines.map { $0.joined(separator: "\n") } ?? text, "revision": 0, "truncated": false,
            ]
            reply(connection, requestID, ["type": "pane_read", "read": read])
        case "agent.send_keys":
            guard pane.agent != nil else {
                return replyError(connection, requestID, code: "agent_not_ready", message: "agent \(target) is not an active named agent")
            }
            let keys = params["keys"] as? [String] ?? []
            if let bad = keys.first(where: { !Self.isKey($0) }) {
                return replyError(connection, requestID, code: "invalid_key", message: "unsupported key \(bad)")
            }
            sentKeys.append((target, keys))
            reply(connection, requestID, ["type": "ok"])
            answer(pane, keys)
        case "agent.prompt":
            let text = params["text"] as? String ?? ""
            guard pane.agent != nil else {
                return replyError(connection, requestID, code: "agent_not_ready", message: "agent \(target) is not an active named agent")
            }
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return replyError(connection, requestID, code: "empty_agent_prompt", message: "agent prompt must not be empty")
            }
            guard pane.status != "blocked" else {
                return replyError(connection, requestID, code: "agent_blocked",
                                  message: "agent \(target) is blocked and requires interactive input")
            }
            sentPrompts.append((target, text))
            reply(connection, requestID, ["type": "agent_prompted", "agent": ["pane_id": target]])
            setStatus(target, "working")
        default:
            let keys = params["keys"] as? [String] ?? []
            sentInput.append((target, params["text"] as? String ?? "", keys))
            reply(connection, requestID, ["type": "ok"])
            answer(pane, keys)
        }
    }

    private func answer(_ pane: FakeHerd.Pane, _ keys: [String]) {
        guard pane.status == "blocked", let last = keys.last?.lowercased() else { return }
        if last == "esc" || last == "escape" {
            setStatus(pane.id, "idle")
        } else if last == "enter" || last == "return" || last.allSatisfy(\.isNumber) {
            setStatus(pane.id, "working")
        }
    }

    static func isKey(_ key: String) -> Bool {
        let key = key.lowercased()
        return key.count == 1 || keyNames.contains(key) || key.hasPrefix("ctrl+")
    }
}

/// Made-up screens in the shape of real agents, for `agent.read`.
public enum FakeScreens {
    public static func screen(kind: String?, status: String) -> String {
        switch (kind, status) {
        case ("codex", "blocked"): codexApproval
        case (_, "blocked"): kind == "claude" ? claudeApproval : question
        case (_, "done"): "Done. All tests pass.\n\n> "
        case (_, "working"): "Reading the project files…\nRunning make test\n"
        default: "> "
        }
    }

    public static let claudeApproval = """
    ⏺ I'll run the tests.

     Bash command

       make test
       Run the test suite

     Do you want to proceed?
     ❯ 1. Yes
       2. Yes, and don't ask again for make commands in /work/app
       3. No, and tell Claude what to do differently (esc)
    """

    public static let codexApproval = """
      Would you like to run the following command?

      $ make test

    › 1. Yes, proceed (y)
      2. Yes, and don't ask again for this command (a)
      3. No, and tell Codex what to do differently (esc)

      Press enter to confirm or esc to cancel
    """

    public static let question = "Which database should the new service use?\n\n> "
}

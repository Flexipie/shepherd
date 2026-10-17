import Foundation
import HerdrKit

/// New tasks: `worktree.create` opens a workspace with one shell pane (a linked worktree of the
/// source workspace's repo, when it has one), and `agent.start` runs an agent in a shell pane,
/// with herdr's checks on names and panes.
extension FakeHerdrServer {
    static let agentKinds: Set<String> = ["claude", "codex", "pi", "opencode", "gemini", "copilot", "amp"]

    func serveTask(_ method: String, _ params: [String: Any], _ connection: LineConnection, _ requestID: String) {
        if method == "worktree.create" {
            let source = params["workspace_id"] as? String ?? ""
            guard let origin = herd.workspaces.first(where: { $0.id == source }) else {
                return replyError(connection, requestID, code: "workspace_not_found", message: "workspace \(source) not found")
            }
            let branch = (params["branch"] as? String) ?? "worktree-\(herd.workspaces.count + 1)"
            let workspace = "w\(herd.workspaces.count + 1)"
            let pane = "\(workspace):p1"
            let repo = origin.repo.map { FakeHerd.Repo(name: $0.name, isLinked: true, checkoutPath: "/work/\(branch)") }
            herd.workspaces.append(FakeHerd.Workspace(id: workspace, label: branch, repo: repo))
            herd.panes.append(FakeHerd.Pane(id: pane, workspaceID: workspace, agent: nil))
            createdWorktrees.append((source, branch))
            reply(connection, requestID, [
                "type": "worktree_created",
                "workspace": ["workspace_id": workspace, "label": branch],
                "tab": ["tab_id": "\(workspace):t1", "workspace_id": workspace],
                "root_pane": ["pane_id": pane, "workspace_id": workspace],
                "worktree": ["branch": branch, "path": "/work/\(branch)", "label": branch],
            ])
            emit("workspace_created", data: ["workspace_id": workspace])
            emit("pane_created", data: ["pane_id": pane, "workspace_id": workspace])
            return
        }
        let name = params["name"] as? String ?? ""
        let kind = params["kind"] as? String ?? ""
        let paneID = params["pane_id"] as? String ?? ""
        guard Self.validName(name) else {
            return replyError(connection, requestID, code: "invalid_agent_name", message: "invalid agent name \(name)")
        }
        guard Self.agentKinds.contains(kind) else {
            return replyError(connection, requestID, code: "unsupported_agent_kind", message: "unsupported agent kind \(kind)")
        }
        guard !startedAgents.contains(where: { $0.name == name }) else {
            return replyError(connection, requestID, code: "agent_name_conflict", message: "agent name \(name) is taken")
        }
        guard let index = herd.panes.firstIndex(where: { $0.id == paneID }) else {
            return replyError(connection, requestID, code: "pane_not_found", message: "pane \(paneID) not found")
        }
        guard herd.panes[index].agent == nil else {
            return replyError(connection, requestID, code: "target_busy", message: "pane \(paneID) is busy")
        }
        startedAgents.append((name, kind, paneID, params["args"] as? [String] ?? []))
        detectAgent(paneID, kind: kind, status: "idle")
        reply(connection, requestID, ["type": "agent_started", "agent": ["pane_id": paneID, "name": name],
                                      "argv": [kind] + (params["args"] as? [String] ?? [])])
    }

    static func validName(_ name: String) -> Bool {
        guard let first = name.first, first.isASCII, first.isLowercase, name.count <= 32 else { return false }
        return name.allSatisfy { ($0.isASCII && ($0.isLowercase || $0.isNumber)) || $0 == "-" || $0 == "_" }
    }
}

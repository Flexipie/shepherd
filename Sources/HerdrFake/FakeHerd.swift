import Foundation

/// The state a fake herdr serves. These are deliberately separate Encodable types written in
/// herdr's wire format, not HerdrKit's models, so a decoding bug cannot hide behind a matching
/// encoder.
public struct FakeHerd: Sendable, Equatable {
    public struct Workspace: Sendable, Equatable {
        public var id: String
        public var label: String
        public var tokens: [String: String] = [:]

        public init(id: String, label: String, tokens: [String: String] = [:]) {
            self.id = id
            self.label = label
            self.tokens = tokens
        }
    }

    public struct Pane: Sendable, Equatable {
        public var id: String
        public var workspaceID: String
        public var terminalID: String
        /// The agent kind; nil for a plain shell pane.
        public var agent: String?
        public var status: String
        public var stateChangeSeq: UInt64 = 0
        public var completionSeq: UInt64? = nil

        public init(id: String, workspaceID: String, terminalID: String? = nil, agent: String? = "claude",
                    status: String = "idle", stateChangeSeq: UInt64 = 1, completionSeq: UInt64? = nil) {
            self.id = id
            self.workspaceID = workspaceID
            self.terminalID = terminalID ?? "term-\(id)"
            self.agent = agent
            self.status = agent == nil ? "unknown" : status
            self.stateChangeSeq = stateChangeSeq
            self.completionSeq = completionSeq
        }
    }

    public var version = "0.0.0-fake"
    public var protocolVersion = 22
    public var workspaces: [Workspace]
    public var panes: [Pane]
    public var focusedPaneID: String?

    public init(workspaces: [Workspace] = [], panes: [Pane] = []) {
        self.workspaces = workspaces
        self.panes = panes
    }

    /// Two workspaces with three agents and a shell pane.
    public static let basic = FakeHerd(
        workspaces: [Workspace(id: "w1", label: "workspace 1"), Workspace(id: "w2", label: "workspace 2")],
        panes: [
            Pane(id: "w1:p1", workspaceID: "w1", status: "working"),
            Pane(id: "w1:p2", workspaceID: "w1", agent: nil),
            Pane(id: "w2:p1", workspaceID: "w2", agent: "codex", status: "idle"),
            Pane(id: "w2:p2", workspaceID: "w2", status: "working"),
        ])

    /// Changes a pane's status the way herdr does: every change bumps `state_change_seq`, and
    /// leaving `working` completes a turn.
    public mutating func setStatus(_ paneID: String, _ status: String) {
        guard let index = panes.firstIndex(where: { $0.id == paneID }), panes[index].status != status else { return }
        if panes[index].status == "working" { panes[index].completionSeq = (panes[index].completionSeq ?? 0) + 1 }
        panes[index].status = status
        panes[index].stateChangeSeq += 1
    }

    public func status(of paneID: String) -> String? {
        panes.first { $0.id == paneID }?.status
    }

    /// The `session.snapshot` result object.
    func snapshotJSON() -> [String: Any] {
        let tabs = workspaces.map { workspace -> [String: Any] in
            ["tab_id": "\(workspace.id):t1", "workspace_id": workspace.id, "number": 1, "label": "tab",
             "focused": false, "pane_count": panes.filter { $0.workspaceID == workspace.id }.count,
             "agent_status": "idle"]
        }
        var result: [String: Any] = [
            "version": version, "protocol": protocolVersion,
            "workspaces": workspaces.enumerated().map { index, workspace in workspaceJSON(workspace, number: index + 1) },
            "tabs": tabs, "layouts": [], "panes": panes.map(paneJSON),
            "agents": panes.filter { $0.agent != nil }.map(agentJSON),
        ]
        if let focusedPaneID { result["focused_pane_id"] = focusedPaneID }
        return result
    }

    private func workspaceJSON(_ workspace: Workspace, number: Int) -> [String: Any] {
        let own = panes.filter { $0.workspaceID == workspace.id }
        var json: [String: Any] = [
            "workspace_id": workspace.id, "number": number, "label": workspace.label, "focused": false,
            "pane_count": own.count, "tab_count": 1, "active_tab_id": "\(workspace.id):t1",
            "agent_status": own.first(where: { $0.status == "blocked" })?.status ?? own.first?.status ?? "idle",
        ]
        if !workspace.tokens.isEmpty { json["tokens"] = workspace.tokens }
        return json
    }

    private func paneJSON(_ pane: Pane) -> [String: Any] {
        var json: [String: Any] = [
            "pane_id": pane.id, "workspace_id": pane.workspaceID, "tab_id": "\(pane.workspaceID):t1",
            "terminal_id": pane.terminalID, "focused": pane.id == focusedPaneID, "agent_status": pane.status,
            "revision": pane.stateChangeSeq,
        ]
        if let agent = pane.agent { json["agent"] = agent }
        return json
    }

    private func agentJSON(_ pane: Pane) -> [String: Any] {
        var json = paneJSON(pane)
        json["state_change_seq"] = pane.stateChangeSeq
        json["completion_seq"] = pane.completionSeq.map { $0 as Any } ?? NSNull()
        return json
    }
}

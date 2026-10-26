extension FakeHerd {
    /// The herdr side of demo mode: three made-up projects with an agent waiting on an approval,
    /// one finished, one working and one idle. Fixed, so screenshots of the demo come out the same.
    public static let demo: FakeHerd = {
        var herd = FakeHerd(
            workspaces: [
                Workspace(id: "w1", label: "api", tokens: ["pr": "#42"], repo: Repo(name: "api")),
                Workspace(id: "w2", label: "web", repo: Repo(name: "web")),
                Workspace(id: "w3", label: "docs", repo: Repo(name: "docs")),
            ],
            panes: [
                Pane(id: "w1:p1", workspaceID: "w1", status: "blocked", stateChangeSeq: 4, cwd: "/tmp/api"),
                Pane(id: "w1:p2", workspaceID: "w1", agent: nil, stateChangeSeq: 0),
                Pane(id: "w2:p1", workspaceID: "w2", agent: "codex", status: "working", stateChangeSeq: 3, cwd: "/tmp/web"),
                Pane(id: "w2:p2", workspaceID: "w2", status: "done", stateChangeSeq: 5, completionSeq: 5,
                     tokens: ["summary": "tests pass"], cwd: "/tmp/web"),
                Pane(id: "w3:p1", workspaceID: "w3", status: "idle", stateChangeSeq: 1, cwd: "/tmp/docs"),
            ])
        herd.version = "demo"
        return herd
    }()
}

/// A new task: a fresh checkout of a project's repo, an agent started in it, and its first
/// prompt.
public struct NewTask: Sendable, Equatable {
    /// The project whose repo the checkout is made from.
    public var project: ProjectID
    /// The checkout's branch; nil lets the source pick a name.
    public var branch: String?
    /// The agent to start, such as "claude".
    public var kind: String
    /// The first prompt; empty starts the agent without one.
    public var prompt: String

    public init(project: ProjectID, branch: String? = nil, kind: String, prompt: String) {
        self.project = project
        self.branch = branch
        self.kind = kind
        self.prompt = prompt
    }
}

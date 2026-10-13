import ShepherdCore

/// What the notch bar shows in place of its project columns.
public enum BarStage: Sendable, Equatable {
    case agent(AgentStage)
    case newTask(NewTaskStage)
}

/// One agent opened in the notch bar: its row, its last visible lines and what can be sent to
/// it. The app reads and sends; the view only shows this and reports `StageAction`s.
public struct AgentStage: Sendable, Equatable {
    public let row: PanelAgentRow
    /// Its last visible lines; nil while the first read is on its way.
    public let lines: [String]?
    /// Choices parsed from the lines, offered while the agent is blocked.
    public let choices: [AgentChoice]
    /// Whether keys (a choice's digit, Return, Escape) can be sent.
    public let canSendKeys: Bool
    /// Whether text can be sent: a reply while blocked, a prompt otherwise.
    public let canReply: Bool
    /// The text starts a new turn (a prompt) rather than answering a question.
    public let prompts: Bool
    /// The last read or send that failed, in words.
    public let error: String?
    /// A send is on its way; the controls wait for it.
    public let isSending: Bool

    public init(row: PanelAgentRow, lines: [String]?, choices: [AgentChoice] = [], canSendKeys: Bool = false,
                canReply: Bool = false, prompts: Bool = false, error: String? = nil, isSending: Bool = false) {
        self.row = row
        self.lines = lines
        self.choices = choices
        self.canSendKeys = canSendKeys
        self.canReply = canReply
        self.prompts = prompts
        self.error = error
        self.isSending = isSending
    }

    public var agent: AgentID { row.agent.id }
}

/// The form for a new task: which project's repo, a branch, which agent, its first prompt.
public struct NewTaskStage: Sendable, Equatable {
    /// Projects a task can start in.
    public let projects: [HerdProject]
    /// Picked when the form opens: the project the source has focused, else the first.
    public let suggestedProject: ProjectID?
    /// Agent kinds to offer, the default first.
    public let kinds: [String]
    /// A task is being started; the form waits for it.
    public let isStarting: Bool
    public let error: String?

    public init(projects: [HerdProject], suggestedProject: ProjectID? = nil, kinds: [String], isStarting: Bool = false,
                error: String? = nil) {
        self.projects = projects
        self.suggestedProject = suggestedProject
        self.kinds = kinds
        self.isStarting = isStarting
        self.error = error
    }
}

/// What the stage asks the app to do.
public enum StageAction: Sendable, Equatable {
    /// Open the agent's stage, from its row.
    case open(AgentID)
    /// Open the new task form.
    case newTask
    case close
    /// Press keys in the staged agent, such as `["1"]`.
    case keys([String])
    /// Send text to the staged agent: a reply while it is blocked, a prompt otherwise.
    case reply(String)
    case startTask(NewTask)
}

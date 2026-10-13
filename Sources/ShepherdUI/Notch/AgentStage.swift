import ShepherdCore

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
    /// Whether a typed reply can be sent.
    public let canReply: Bool
    /// The last read or send that failed, in words.
    public let error: String?
    /// A send is on its way; the controls wait for it.
    public let isSending: Bool

    public init(row: PanelAgentRow, lines: [String]?, choices: [AgentChoice] = [], canSendKeys: Bool = false,
                canReply: Bool = false, error: String? = nil, isSending: Bool = false) {
        self.row = row
        self.lines = lines
        self.choices = choices
        self.canSendKeys = canSendKeys
        self.canReply = canReply
        self.error = error
        self.isSending = isSending
    }

    public var agent: AgentID { row.agent.id }
}

/// What the stage asks the app to do.
public enum StageAction: Sendable, Equatable {
    /// Open the agent's stage, from its queue row.
    case open(AgentID)
    case close
    /// Press keys in the staged agent, such as `["1"]`.
    case keys([String])
    /// Type a reply into the staged agent and press Return.
    case reply(String)
}

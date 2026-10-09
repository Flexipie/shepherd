import Foundation

// The source-neutral herd model. Every source (herdr first) adapts its own state to these types;
// modules and surfaces see nothing else.

/// An agent's lifecycle state. `done` means finished and not yet seen.
public enum HerdStatus: String, Sendable, Hashable, Codable, CaseIterable {
    case idle, working, blocked, done, unknown

    /// Blocked or finished-and-unseen: the agent is waiting on the user.
    public var needsYou: Bool { self == .blocked || self == .done }
}

/// When an agent entered its current state. `exact` when Shepherd saw the change; `noLaterThan`
/// when it only knows an upper bound (after a launch or a gap in the source's events).
public struct Since: Sendable, Equatable, Codable {
    public enum Precision: String, Sendable, Equatable, Codable {
        case exact
        case noLaterThan
    }

    public let date: Date
    public let precision: Precision

    public init(_ date: Date, _ precision: Precision) {
        self.date = date
        self.precision = precision
    }
}

/// Which source an agent comes from, such as `herdr`.
public struct SourceID: RawRepresentable, Hashable, Sendable, Codable, ExpressibleByStringLiteral, CustomStringConvertible {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { rawValue = value }
    public var description: String { rawValue }
}

/// An agent's identity: its source plus the source's own id for it.
public struct AgentID: Hashable, Sendable, Codable, CustomStringConvertible {
    public let source: SourceID
    public let local: String

    public init(source: SourceID, local: String) {
        self.source = source
        self.local = local
    }

    public var description: String { "\(source):\(local)" }
}

/// A project's identity: its source plus the source's own id for it (for herdr, a workspace).
public struct ProjectID: Hashable, Sendable, Codable, CustomStringConvertible {
    public let source: SourceID
    public let local: String

    public init(source: SourceID, local: String) {
        self.source = source
        self.local = local
    }

    public var description: String { "\(source):\(local)" }
}

/// A place agents work in, such as a herdr workspace. A project without agents is still shown:
/// it is somewhere the user can go.
public struct HerdProject: Sendable, Equatable, Identifiable {
    public let id: ProjectID
    public let name: String
    /// The project's own tokens; an agent's tokens are on the agent.
    public let tokens: [String: String]
    /// The source's own UI has this project focused.
    public let isFocusedInSource: Bool

    public init(id: ProjectID, name: String, tokens: [String: String] = [:], isFocusedInSource: Bool = false) {
        self.id = id
        self.name = name
        self.tokens = tokens
        self.isFocusedInSource = isFocusedInSource
    }
}

/// One agent as every surface sees it.
public struct HerdAgent: Sendable, Equatable, Identifiable {
    public let id: AgentID
    /// The kind of agent, such as `claude` or `codex`, when the source knows it.
    public let kind: String?
    public let name: String
    /// The project the agent works in, when its source has projects.
    public let projectID: ProjectID?
    /// The project's name, for display.
    public let project: String
    public let status: HerdStatus
    /// A source- or plugin-provided label for the current state, if any.
    public let statusLabel: String?
    public let since: Since?
    /// The agent's own tokens; its project's are on the project.
    public let tokens: [String: String]
    /// The source's own UI has this agent focused, so the user may be looking at it.
    public let isFocusedInSource: Bool

    public init(id: AgentID, kind: String? = nil, name: String, projectID: ProjectID? = nil, project: String = "",
                status: HerdStatus, statusLabel: String? = nil, since: Since? = nil, tokens: [String: String] = [:],
                isFocusedInSource: Bool = false) {
        self.id = id
        self.kind = kind
        self.name = name
        self.projectID = projectID
        self.project = project
        self.status = status
        self.statusLabel = statusLabel
        self.since = since
        self.tokens = tokens
        self.isFocusedInSource = isFocusedInSource
    }
}

/// An observed change to one agent.
public struct HerdTransition: Sendable, Equatable, Codable {
    public let agent: AgentID
    public let kind: String?
    public let project: String
    /// nil when the agent appeared.
    public let from: HerdStatus?
    /// nil when the agent went away.
    public let to: HerdStatus?
    public let at: Date
    public let precision: Since.Precision
    /// Opaque, source-defined. Lets a source tell, after a restart, whether an agent is still in
    /// the state this transition recorded.
    public let marker: String?

    public init(agent: AgentID, kind: String? = nil, project: String = "", from: HerdStatus?, to: HerdStatus?,
                at: Date, precision: Since.Precision = .exact, marker: String? = nil) {
        self.agent = agent
        self.kind = kind
        self.project = project
        self.from = from
        self.to = to
        self.at = at
        self.precision = precision
        self.marker = marker
    }
}

/// How current a source's state is. Shepherd never presents stale state as live.
public enum SourceState: Sendable, Equatable {
    case connecting
    case live
    /// The source's event stream broke; showing its last known state while recovering.
    case stale(String)
    /// The source is not running or not reachable; retrying.
    case disconnected(String)

    public var isLive: Bool { self == .live }
}

/// What a source can do. Surfaces hide what a source cannot do instead of failing.
public struct SourceCapabilities: OptionSet, Sendable, Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let focus = SourceCapabilities(rawValue: 1 << 0)
    public static let readOutput = SourceCapabilities(rawValue: 1 << 1)
    public static let prompt = SourceCapabilities(rawValue: 1 << 2)
    public static let sendKeys = SourceCapabilities(rawValue: 1 << 3)
    public static let approve = SourceCapabilities(rawValue: 1 << 4)
    public static let startAgent = SourceCapabilities(rawValue: 1 << 5)
    public static let createWorktree = SourceCapabilities(rawValue: 1 << 6)
    public static let focusProject = SourceCapabilities(rawValue: 1 << 7)
}

/// Everything a source publishes at once.
public struct SourceUpdate: Sendable, Equatable {
    public let agents: [HerdAgent]
    /// The source's projects, in the source's own order.
    public let projects: [HerdProject]
    public let state: SourceState
    /// Short lines about the source for the menu, such as its version or a compatibility warning.
    public let statusLines: [String]
    /// Transitions observed since the previous update.
    public let transitions: [HerdTransition]
    /// The source's own token styling (for herdr, its sidebar config), if it has any.
    public let tokenLayout: TokenLayout?

    public init(agents: [HerdAgent], projects: [HerdProject] = [], state: SourceState, statusLines: [String] = [],
                transitions: [HerdTransition] = [], tokenLayout: TokenLayout? = nil) {
        self.agents = agents
        self.projects = projects
        self.state = state
        self.statusLines = statusLines
        self.transitions = transitions
        self.tokenLayout = tokenLayout
    }
}

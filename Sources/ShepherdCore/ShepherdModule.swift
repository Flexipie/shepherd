import HerdrKit

/// A Shepherd feature. Every feature is one module in `Sources/ShepherdModules/<Name>/`, listed
/// in `BuiltinModules.all`. A module reads the shared `ModuleContext` and offers contributions;
/// the app decides where and how they are drawn. Contributions are read inside observation
/// tracking, so a module that derives them from observable state is redrawn when that state
/// changes, and only then.
@MainActor
public protocol ShepherdModule: AnyObject {
    /// Stable id used in config to enable, disable and order modules.
    static var id: String { get }

    init(context: ModuleContext)

    /// What the menu bar item shows.
    var status: StatusContribution? { get }

    /// What the notch pill shows, if anything.
    var notch: NotchItem? { get }
}

extension ShepherdModule {
    public var status: StatusContribution? { nil }
    public var notch: NotchItem? { nil }
}

/// A menu bar glyph with an optional count.
public struct StatusContribution: Sendable, Equatable {
    public enum Emphasis: Sendable, Equatable {
        case normal
        /// Something needs the user.
        case attention
        /// The shown state is not live (herdr down, stream broken).
        case dimmed
    }

    public let symbol: String
    public let count: Int?
    public let emphasis: Emphasis
    public let accessibilityLabel: String

    public init(symbol: String, count: Int? = nil, emphasis: Emphasis = .normal, accessibilityLabel: String) {
        self.symbol = symbol
        self.count = count
        self.emphasis = emphasis
        self.accessibilityLabel = accessibilityLabel
    }
}

/// One agent the notch pill should show.
public struct NotchItem: Sendable, Equatable {
    public enum Reason: Sendable, Equatable {
        case blocked
        case finished
    }

    public let agent: AgentState
    public let reason: Reason
    /// Other agents also waiting, shown as "+N".
    public let others: Int

    public init(agent: AgentState, reason: Reason, others: Int) {
        self.agent = agent
        self.reason = reason
        self.others = others
    }

    public var title: String { agent.agent.displayName }
    public var subtitle: String {
        let label = agent.agent.stateLabels[agent.status.rawValue]
        let reasonText = label ?? (reason == .blocked ? "needs you" : "finished")
        return agent.workspaceLabel.isEmpty ? reasonText : "\(agent.workspaceLabel) · \(reasonText)"
    }
}

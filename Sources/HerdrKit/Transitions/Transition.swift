import Foundation

/// When an agent entered its current state, as far as Shepherd can tell. herdr's snapshot has no
/// timestamps, so Shepherd records when it observed each change. After a launch or a gap in the
/// event stream it only knows the state began no later than when it looked.
public struct StateSince: Sendable, Equatable {
    public enum Precision: Sendable, Equatable {
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

/// Whether the event stream was uninterrupted between the previous snapshot and this one.
public enum Continuity: Sendable, Equatable {
    case continuous
    case afterGap
}

/// An observed change to one agent between two snapshots.
public struct Transition: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case changed
        case appeared
        case closed
    }

    public let paneID: String
    public let kind: Kind
    public let from: AgentStatus?
    public let to: AgentStatus?
    public let observedAt: Date
    /// A working turn completed between the two snapshots. herdr's counters are shared by every
    /// agent, so how many turns, or how many changes Shepherd missed, cannot be told.
    public let completedTurn: Bool
    /// The pane's terminal and change counter after the transition, so a later run can tell
    /// whether the agent is still in this state.
    public let terminalID: String?
    public let stateChangeSeq: UInt64

    package init(paneID: String, kind: Kind, from: AgentStatus?, to: AgentStatus?, observedAt: Date,
                 completedTurn: Bool = false, terminalID: String? = nil, stateChangeSeq: UInt64 = 0) {
        self.terminalID = terminalID
        self.stateChangeSeq = stateChangeSeq
        self.paneID = paneID
        self.kind = kind
        self.from = from
        self.to = to
        self.observedAt = observedAt
        self.completedTurn = completedTurn
    }
}

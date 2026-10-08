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
    /// Transitions herdr made between the two snapshots that Shepherd did not see.
    public let missedChanges: UInt64
    /// Working turns completed between the two snapshots.
    public let completedTurns: UInt64
}

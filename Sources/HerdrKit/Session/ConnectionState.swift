import Foundation

/// How current the shown state is. Shepherd never presents stale state as live.
public enum ConnectionState: Sendable, Equatable {
    /// Starting up; nothing read yet.
    case connecting
    /// Subscribed and reconciled with a fresh snapshot.
    case live
    /// The event stream broke; showing the last known state while recovering.
    case stale(String)
    /// herdr is not running or not reachable; retrying.
    case disconnected(String)

    public var isLive: Bool { self == .live }
}

/// What the engine publishes after each change.
public struct SessionUpdate: Sendable, Equatable {
    public let session: Session
    public let connection: ConnectionState
    public let compatibility: Compatibility
    /// Transitions observed by the snapshot that produced this update.
    public let transitions: [Transition]

    package init(session: Session, connection: ConnectionState, compatibility: Compatibility, transitions: [Transition]) {
        self.session = session
        self.connection = connection
        self.compatibility = compatibility
        self.transitions = transitions
    }
}

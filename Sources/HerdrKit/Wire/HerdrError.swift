import Foundation

/// Everything that can go wrong talking to herdr.
public enum HerdrError: Error, Sendable, Equatable {
    /// No socket, or nothing listening on it: herdr is not running.
    case notRunning
    case permissionDenied
    case socketPathTooLong(String)
    case timeout
    /// The peer closed the connection.
    case disconnected
    case lineTooLong
    case io(Int32)
    /// herdr answered with an error response.
    case server(ServerErrorCode, message: String)
    /// herdr answered with something Shepherd cannot use.
    case unexpectedResponse(String)
}

/// herdr's error codes are open-ended; the ones Shepherd reacts to have names.
public struct ServerErrorCode: RawRepresentable, Hashable, Sendable, Decodable, CustomStringConvertible {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }
    public var description: String { rawValue }

    /// The subscriber fell behind herdr's event history; herdr closes the subscription.
    public static let eventsLost = ServerErrorCode(rawValue: "events_lost")
    /// A subscription named a pane that does not exist; herdr rejects the whole request.
    public static let paneNotFound = ServerErrorCode(rawValue: "pane_not_found")
}

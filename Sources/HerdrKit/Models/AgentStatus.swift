import Foundation

/// herdr's agent lifecycle state. `done` means finished and not yet seen; focusing the pane
/// through the API marks it seen and it becomes `idle`. Unknown values from newer herdr builds
/// decode as `unrecognized` instead of failing.
public enum AgentStatus: Sendable, Hashable, Codable, CustomStringConvertible {
    case idle, working, blocked, done, unknown
    case unrecognized(String)

    public init(rawValue: String) {
        switch rawValue {
        case "idle": self = .idle
        case "working": self = .working
        case "blocked": self = .blocked
        case "done": self = .done
        case "unknown": self = .unknown
        default: self = .unrecognized(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .idle: "idle"
        case .working: "working"
        case .blocked: "blocked"
        case .done: "done"
        case .unknown: "unknown"
        case .unrecognized(let value): value
        }
    }

    public var description: String { rawValue }

    /// Blocked or finished-and-unseen: the agent is waiting on the user.
    public var needsYou: Bool { self == .blocked || self == .done }

    public init(from decoder: any Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

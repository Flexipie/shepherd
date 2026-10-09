/// A config value of any shape, so settings written in JSON (Shepherd's config) and TOML
/// (herdr's) are read by the same code.
public enum ConfigValue: Sendable, Equatable, Decodable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([ConfigValue])
    case table([String: ConfigValue])
    case null

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([ConfigValue].self) { self = .array(value) }
        else { self = .table(try container.decode([String: ConfigValue].self)) }
    }

    /// How the value is described in a problem message.
    public var kind: String {
        switch self {
        case .string: "a string"
        case .number: "a number"
        case .bool: "true or false"
        case .array: "a list"
        case .table: "an object"
        case .null: "null"
        }
    }
}

/// A config value that could not be used, with a message for the user.
public struct ConfigProblem: Error, Sendable, Equatable, CustomStringConvertible {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var description: String { message }
}

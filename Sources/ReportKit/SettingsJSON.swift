import Foundation

/// A JSON value that keeps object keys in file order and numbers as written, so an agent's
/// settings file can be edited and printed back with only the edited lines changed.
/// `JSONSerialization` loses the order, which would turn every install into a rewrite.
public indirect enum SettingsJSON: Equatable, Sendable {
    case object([(key: String, value: SettingsJSON)])
    case array([SettingsJSON])
    case string(String)
    /// The number's text as written, never reformatted.
    case number(String)
    case bool(Bool)
    case null

    public static func == (lhs: SettingsJSON, rhs: SettingsJSON) -> Bool {
        switch (lhs, rhs) {
        case let (.object(a), .object(b)):
            a.count == b.count && zip(a, b).allSatisfy { $0.key == $1.key && $0.value == $1.value }
        case let (.array(a), .array(b)): a == b
        case let (.string(a), .string(b)): a == b
        case let (.number(a), .number(b)): a == b
        case let (.bool(a), .bool(b)): a == b
        case (.null, .null): true
        default: false
        }
    }

    /// The value for `key` in an object, nil for a missing key or a non-object.
    public subscript(key: String) -> SettingsJSON? {
        guard case let .object(pairs) = self else { return nil }
        return pairs.first { $0.key == key }?.value
    }

    public var string: String? {
        if case let .string(value) = self { return value }
        return nil
    }

    // MARK: Printing

    /// Two-space indentation, `": "` after keys and a final newline: what Claude Code writes, so a
    /// file it wrote prints back byte for byte.
    public func printed() -> String {
        var out = ""
        write(to: &out, indent: "")
        return out + "\n"
    }

    private func write(to out: inout String, indent: String) {
        let inner = indent + "  "
        switch self {
        case let .object(pairs):
            guard !pairs.isEmpty else { out += "{}"; return }
            out += "{\n"
            for (index, pair) in pairs.enumerated() {
                out += inner + Self.quoted(pair.key) + ": "
                pair.value.write(to: &out, indent: inner)
                out += index == pairs.count - 1 ? "\n" : ",\n"
            }
            out += indent + "}"
        case let .array(items):
            guard !items.isEmpty else { out += "[]"; return }
            out += "[\n"
            for (index, item) in items.enumerated() {
                out += inner
                item.write(to: &out, indent: inner)
                out += index == items.count - 1 ? "\n" : ",\n"
            }
            out += indent + "]"
        case let .string(value): out += Self.quoted(value)
        case let .number(text): out += text
        case let .bool(value): out += value ? "true" : "false"
        case .null: out += "null"
        }
    }

    /// Escapes as JavaScript's `JSON.stringify` does: quotes, backslashes and control characters.
    static func quoted(_ text: String) -> String {
        var out = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            case _ where scalar.value < 0x20: out += String(format: "\\u%04x", scalar.value)
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out + "\""
    }

    // MARK: Parsing

    public struct ParseError: Error, Equatable, CustomStringConvertible {
        public let offset: Int
        public let reason: String
        public var description: String { "\(reason) at byte \(offset)" }
    }

    /// Strict JSON. Anything else, comments and trailing commas included, throws.
    public static func parse(_ data: Data) throws -> SettingsJSON {
        var parser = Parser(bytes: Array(data))
        let value = try parser.value()
        parser.skipSpace()
        guard parser.index == parser.bytes.count else { throw parser.error("unexpected text after the value") }
        return value
    }

    private struct Parser {
        let bytes: [UInt8]
        var index = 0

        func error(_ reason: String) -> ParseError { ParseError(offset: index, reason: reason) }

        mutating func skipSpace() {
            while index < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[index]) { index += 1 }
        }

        mutating func expect(_ byte: UInt8) throws {
            skipSpace()
            guard index < bytes.count, bytes[index] == byte else {
                throw error("expected \(Character(UnicodeScalar(byte)))")
            }
            index += 1
        }

        mutating func literal(_ word: String) -> Bool {
            let utf8 = Array(word.utf8)
            guard bytes.count - index >= utf8.count, Array(bytes[index..<index + utf8.count]) == utf8 else { return false }
            index += utf8.count
            return true
        }

        mutating func value() throws -> SettingsJSON {
            skipSpace()
            guard index < bytes.count else { throw error("unexpected end") }
            switch bytes[index] {
            case UInt8(ascii: "{"): return try object()
            case UInt8(ascii: "["): return try array()
            case UInt8(ascii: "\""): return .string(try string())
            case UInt8(ascii: "t") where literal("true"): return .bool(true)
            case UInt8(ascii: "f") where literal("false"): return .bool(false)
            case UInt8(ascii: "n") where literal("null"): return .null
            default: return try number()
            }
        }

        mutating func object() throws -> SettingsJSON {
            index += 1
            var pairs: [(key: String, value: SettingsJSON)] = []
            skipSpace()
            if index < bytes.count, bytes[index] == UInt8(ascii: "}") { index += 1; return .object(pairs) }
            while true {
                skipSpace()
                guard index < bytes.count, bytes[index] == UInt8(ascii: "\"") else { throw error("expected a key") }
                let key = try string()
                try expect(UInt8(ascii: ":"))
                pairs.append((key, try value()))
                skipSpace()
                guard index < bytes.count else { throw error("unexpected end") }
                if bytes[index] == UInt8(ascii: ",") { index += 1; continue }
                if bytes[index] == UInt8(ascii: "}") { index += 1; return .object(pairs) }
                throw error("expected , or }")
            }
        }

        mutating func array() throws -> SettingsJSON {
            index += 1
            var items: [SettingsJSON] = []
            skipSpace()
            if index < bytes.count, bytes[index] == UInt8(ascii: "]") { index += 1; return .array(items) }
            while true {
                items.append(try value())
                skipSpace()
                guard index < bytes.count else { throw error("unexpected end") }
                if bytes[index] == UInt8(ascii: ",") { index += 1; continue }
                if bytes[index] == UInt8(ascii: "]") { index += 1; return .array(items) }
                throw error("expected , or ]")
            }
        }

        /// The string's text, read from the opening quote. Escapes are decoded by
        /// `JSONSerialization` on the raw slice, which also checks them.
        mutating func string() throws -> String {
            let start = index
            index += 1
            while index < bytes.count {
                switch bytes[index] {
                case UInt8(ascii: "\\"): index += 2
                case UInt8(ascii: "\""):
                    index += 1
                    let slice = Data(bytes[start..<index])
                    guard let text = try? JSONSerialization.jsonObject(with: slice, options: .fragmentsAllowed) as? String else {
                        throw ParseError(offset: start, reason: "bad string")
                    }
                    return text
                case 0x00..<0x20: throw error("control character in a string")
                default: index += 1
                }
            }
            throw ParseError(offset: start, reason: "unterminated string")
        }

        mutating func number() throws -> SettingsJSON {
            let start = index
            while index < bytes.count, "+-0123456789.eE".utf8.contains(bytes[index]) { index += 1 }
            let text = String(decoding: bytes[start..<index], as: UTF8.self)
            guard !text.isEmpty, (try? JSONSerialization.jsonObject(with: Data(text.utf8), options: .fragmentsAllowed)) is NSNumber else {
                throw ParseError(offset: start, reason: "unexpected text")
            }
            return .number(text)
        }
    }
}

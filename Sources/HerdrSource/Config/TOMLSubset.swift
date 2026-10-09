import Foundation

/// A small TOML reader, enough to find herdr's sidebar settings in a real config file. It reads
/// every table and value so it can get past the whole file (`[keys]`, `[[keys.command]]`, comments,
/// multi-line arrays), keeps strings, numbers, booleans, arrays and inline tables, and keeps other
/// values (dates, multi-line strings) as opaque. A malformed line is recorded and reading resumes
/// at the next table header, so one mistake never hides the rest of the file.
struct TOMLDocument {
    indirect enum Value: Equatable {
        case string(String)
        case integer(Int64)
        case float(Double)
        case bool(Bool)
        case array([Value])
        case table([String: Value])
        /// Read past but not interpreted.
        case opaque(String)
    }

    struct Assignment: Equatable {
        /// Header path plus the dotted key. Keys under `[[array.tables]]` get a `[]` component so
        /// they never match an ordinary path.
        let path: [String]
        let value: Value
        let line: Int
    }

    struct Problem: Error, Equatable {
        let line: Int
        let message: String
    }

    var assignments: [Assignment] = []
    var problems: [Problem] = []

    init(_ data: Data) {
        var reader = TOMLReader(bytes: Array(data))
        reader.read(into: &self)
    }

    /// The value at a dotted path, looking inside inline tables when the path continues into one.
    func value(at path: [String]) -> (value: Value, line: Int)? {
        for assignment in assignments.reversed() where path.starts(with: assignment.path) {
            var value = assignment.value
            var found = true
            for key in path.dropFirst(assignment.path.count) {
                guard case .table(let table) = value, let next = table[key] else {
                    found = false
                    break
                }
                value = next
            }
            if found { return (value, assignment.line) }
        }
        return nil
    }
}

private struct TOMLReader {
    let bytes: [UInt8]
    var index = 0
    var line = 1

    init(bytes: [UInt8]) {
        self.bytes = bytes
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { index = 3 }
    }

    var peek: UInt8? { index < bytes.count ? bytes[index] : nil }

    func peek(_ offset: Int) -> UInt8? { index + offset < bytes.count ? bytes[index + offset] : nil }

    mutating func advance() {
        if bytes[index] == UInt8(ascii: "\n") { line += 1 }
        index += 1
    }

    mutating func read(into document: inout TOMLDocument) {
        var header: [String] = []
        while true {
            skipBlank(newlines: true)
            guard let byte = peek else { return }
            let start = line
            let startIndex = index
            do {
                if byte == UInt8(ascii: "[") {
                    header = try readHeader()
                } else {
                    let key = try readKey()
                    skipBlank(newlines: false)
                    try expect("=")
                    skipBlank(newlines: false)
                    let value = try readValue()
                    try endOfLine()
                    document.assignments.append(.init(path: header + key, value: value, line: start))
                }
            } catch {
                document.problems.append(error as? TOMLDocument.Problem ?? fail("\(error)"))
                header = ["[]"]
                skipToNextHeader(after: startIndex)
            }
        }
    }

    // MARK: Structure

    mutating func readHeader() throws -> [String] {
        advance()
        let arrayTable = peek == UInt8(ascii: "[")
        if arrayTable { advance() }
        skipBlank(newlines: false)
        let key = try readKey()
        skipBlank(newlines: false)
        try expect("]")
        if arrayTable { try expect("]") }
        try endOfLine()
        return arrayTable ? key + ["[]"] : key
    }

    /// `a.b."c d".'e'`
    mutating func readKey() throws -> [String] {
        var parts: [String] = []
        while true {
            skipBlank(newlines: false)
            switch peek {
            case UInt8(ascii: "\"")?: parts.append(try readBasicString())
            case UInt8(ascii: "'")?: parts.append(try readLiteralString())
            default:
                let bare = take { Self.isBare($0) }
                guard !bare.isEmpty else { throw fail("expected a key") }
                parts.append(bare)
            }
            skipBlank(newlines: false)
            guard peek == UInt8(ascii: ".") else { return parts }
            advance()
        }
    }

    mutating func readValue() throws -> TOMLDocument.Value {
        guard let byte = peek else { throw fail("expected a value") }
        switch byte {
        case UInt8(ascii: "\""):
            if peek(1) == byte, peek(2) == byte { return .opaque(try skipMultiline(byte)) }
            return .string(try readBasicString())
        case UInt8(ascii: "'"):
            if peek(1) == byte, peek(2) == byte { return .opaque(try skipMultiline(byte)) }
            return .string(try readLiteralString())
        case UInt8(ascii: "["): return try readArray()
        case UInt8(ascii: "{"): return try readInlineTable()
        default: return try readScalar()
        }
    }

    mutating func readArray() throws -> TOMLDocument.Value {
        advance()
        var items: [TOMLDocument.Value] = []
        while true {
            skipBlank(newlines: true)
            if peek == UInt8(ascii: "]") {
                advance()
                return .array(items)
            }
            items.append(try readValue())
            skipBlank(newlines: true)
            if peek == UInt8(ascii: ",") { advance() } else if peek != UInt8(ascii: "]") { throw fail("expected , or ] in a list") }
        }
    }

    /// Lenient like TOML 1.1: newlines, comments and a trailing comma are allowed.
    mutating func readInlineTable() throws -> TOMLDocument.Value {
        advance()
        var table: [String: TOMLDocument.Value] = [:]
        while true {
            skipBlank(newlines: true)
            if peek == UInt8(ascii: "}") {
                advance()
                return .table(table)
            }
            let key = try readKey()
            skipBlank(newlines: false)
            try expect("=")
            skipBlank(newlines: false)
            table = Self.insert(try readValue(), at: key[...], into: table)
            skipBlank(newlines: true)
            if peek == UInt8(ascii: ",") { advance() } else if peek != UInt8(ascii: "}") { throw fail("expected , or } in an inline table") }
        }
    }

    static func insert(_ value: TOMLDocument.Value, at key: ArraySlice<String>, into table: [String: TOMLDocument.Value])
        -> [String: TOMLDocument.Value] {
        var table = table
        guard let first = key.first else { return table }
        if key.count == 1 {
            table[first] = value
        } else {
            let inner = if case .table(let existing)? = table[first] { existing } else { [String: TOMLDocument.Value]() }
            table[first] = .table(insert(value, at: key.dropFirst(), into: inner))
        }
        return table
    }

    /// Booleans, numbers, and anything else bare (dates) kept opaque.
    mutating func readScalar() throws -> TOMLDocument.Value {
        var text = take { Self.isBare($0) || $0 == UInt8(ascii: "+") || $0 == UInt8(ascii: ".") || $0 == UInt8(ascii: ":") }
        // A date and time may be separated by a space.
        if text.count == 10, text.dropFirst(4).first == "-", peek == UInt8(ascii: " "), let next = peek(1), Self.isDigit(next) {
            advance()
            text += " " + take { Self.isBare($0) || $0 == UInt8(ascii: ":") || $0 == UInt8(ascii: ".") || $0 == UInt8(ascii: "+") }
        }
        switch text {
        case "": throw fail("expected a value")
        case "true": return .bool(true)
        case "false": return .bool(false)
        case "inf", "+inf": return .float(.infinity)
        case "-inf": return .float(-.infinity)
        case "nan", "+nan", "-nan": return .float(.nan)
        default: break
        }
        let plain = text.replacingOccurrences(of: "_", with: "")
        for (prefix, radix) in [("0x", 16), ("0o", 8), ("0b", 2)] where plain.hasPrefix(prefix) {
            guard let value = Int64(plain.dropFirst(2), radix: radix) else { throw fail("invalid number \(text)") }
            return .integer(value)
        }
        if let value = Int64(plain) { return .integer(value) }
        if plain.first.map({ $0.isNumber || $0 == "+" || $0 == "-" || $0 == "." }) == true,
           plain.allSatisfy({ $0.isNumber || "+-.eE".contains($0) }), let value = Double(plain) {
            return .float(value)
        }
        if let first = text.first, first.isNumber, text.contains(where: { $0 == "-" || $0 == ":" }) { return .opaque(text) }
        throw fail("invalid value \(text)")
    }

    // MARK: Strings

    mutating func readBasicString() throws -> String {
        advance()
        var scalars = String.UnicodeScalarView()
        var raw: [UInt8] = []
        func flush() {
            scalars.append(contentsOf: String(decoding: raw, as: UTF8.self).unicodeScalars)
            raw.removeAll()
        }
        while let byte = peek {
            switch byte {
            case UInt8(ascii: "\""):
                advance()
                flush()
                return String(scalars)
            case UInt8(ascii: "\n"):
                throw fail("unterminated string")
            case UInt8(ascii: "\\"):
                advance()
                guard let escape = peek else { throw fail("unterminated string") }
                advance()
                flush()
                switch escape {
                case UInt8(ascii: "b"): scalars.append("\u{08}")
                case UInt8(ascii: "t"): scalars.append("\t")
                case UInt8(ascii: "n"): scalars.append("\n")
                case UInt8(ascii: "f"): scalars.append("\u{0C}")
                case UInt8(ascii: "r"): scalars.append("\r")
                case UInt8(ascii: "e"): scalars.append("\u{1B}")
                case UInt8(ascii: "\""): scalars.append("\"")
                case UInt8(ascii: "\\"): scalars.append("\\")
                case UInt8(ascii: "u"), UInt8(ascii: "U"):
                    let count = escape == UInt8(ascii: "u") ? 4 : 8
                    guard index + count <= bytes.count,
                          let code = UInt32(String(decoding: bytes[index..<index + count], as: UTF8.self), radix: 16),
                          let scalar = Unicode.Scalar(code) else { throw fail("invalid unicode escape") }
                    index += count
                    scalars.append(scalar)
                default:
                    throw fail("invalid escape \\\(Character(Unicode.Scalar(escape)))")
                }
            default:
                raw.append(byte)
                advance()
            }
        }
        throw fail("unterminated string")
    }

    mutating func readLiteralString() throws -> String {
        advance()
        let start = index
        while let byte = peek, byte != UInt8(ascii: "'") {
            if byte == UInt8(ascii: "\n") { throw fail("unterminated string") }
            advance()
        }
        guard peek != nil else { throw fail("unterminated string") }
        let text = String(decoding: bytes[start..<index], as: UTF8.self)
        advance()
        return text
    }

    /// `"""…"""` or `'''…'''`, read past without interpreting.
    mutating func skipMultiline(_ quote: UInt8) throws -> String {
        let start = index
        for _ in 0..<3 { advance() }
        while let byte = peek {
            if quote == UInt8(ascii: "\""), byte == UInt8(ascii: "\\") {
                advance()
                if peek != nil { advance() }
                continue
            }
            if byte == quote, peek(1) == quote, peek(2) == quote {
                for _ in 0..<3 { advance() }
                // Up to two more quotes may close the string as part of its content.
                for _ in 0..<2 where peek == quote { advance() }
                return String(decoding: bytes[start..<index], as: UTF8.self)
            }
            advance()
        }
        throw fail("unterminated multi-line string")
    }

    // MARK: Whitespace and errors

    /// Spaces, tabs and comments; with `newlines`, line breaks too.
    mutating func skipBlank(newlines: Bool) {
        while let byte = peek {
            if byte == UInt8(ascii: " ") || byte == UInt8(ascii: "\t") || byte == UInt8(ascii: "\r") {
                advance()
            } else if byte == UInt8(ascii: "#") {
                while let next = peek, next != UInt8(ascii: "\n") { advance() }
            } else if newlines, byte == UInt8(ascii: "\n") {
                advance()
            } else {
                return
            }
        }
    }

    mutating func endOfLine() throws {
        skipBlank(newlines: false)
        guard let byte = peek else { return }
        guard byte == UInt8(ascii: "\n") else { throw fail("unexpected text after a value") }
        advance()
    }

    /// After an error: on to the next line that starts with `[`, a table header. That may be the
    /// line the error is on, as when an unclosed list runs into the next table.
    mutating func skipToNextHeader(after statement: Int) {
        var lineStart = index
        while lineStart > 0, bytes[lineStart - 1] != UInt8(ascii: "\n") { lineStart -= 1 }
        if lineStart > statement, bytes[lineStart] == UInt8(ascii: "[") {
            index = lineStart
            return
        }
        while let byte = peek {
            let lineStart = index == 0 || bytes[index - 1] == UInt8(ascii: "\n")
            if lineStart, byte == UInt8(ascii: "[") { return }
            advance()
        }
    }

    mutating func expect(_ character: Character) throws {
        guard let ascii = character.asciiValue, peek == ascii else { throw fail("expected \(character)") }
        advance()
    }

    mutating func take(while accept: (UInt8) -> Bool) -> String {
        let start = index
        while let byte = peek, accept(byte) { advance() }
        return String(decoding: bytes[start..<index], as: UTF8.self)
    }

    func fail(_ message: String) -> TOMLDocument.Problem {
        TOMLDocument.Problem(line: line, message: message)
    }

    static func isDigit(_ byte: UInt8) -> Bool { (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) }

    static func isBare(_ byte: UInt8) -> Bool {
        isDigit(byte) || (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(byte) || (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(byte)
            || byte == UInt8(ascii: "_") || byte == UInt8(ascii: "-")
    }
}

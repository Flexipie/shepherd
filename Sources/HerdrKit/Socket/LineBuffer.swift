import Foundation

/// Splits a byte stream into newline-delimited lines. Blank lines are skipped and a trailing
/// carriage return is dropped. A line longer than `maxLineLength` is an error, so a broken peer
/// cannot make Shepherd buffer without bound.
package struct LineBuffer: Sendable {
    package static let defaultMaxLineLength = 32 << 20

    package let maxLineLength: Int
    private var pending: [UInt8] = []
    private var scanned = 0

    package init(maxLineLength: Int = LineBuffer.defaultMaxLineLength) {
        self.maxLineLength = maxLineLength
    }

    /// Appends bytes and returns every line they complete.
    package mutating func append(_ bytes: some Collection<UInt8>) throws -> [Data] {
        pending.append(contentsOf: bytes)
        var lines: [Data] = []
        var start = 0
        var index = scanned
        while let newline = pending[index...].firstIndex(of: 0x0A) {
            var end = newline
            if end > start, pending[end - 1] == 0x0D { end -= 1 }
            if end > start { lines.append(Data(pending[start..<end])) }
            start = newline + 1
            index = start
        }
        if start > 0 { pending.removeFirst(start) }
        scanned = pending.count
        if pending.count > maxLineLength { throw HerdrError.lineTooLong }
        return lines
    }
}

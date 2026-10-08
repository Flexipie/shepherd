import Foundation
import Testing
@testable import HerdrKit

@Suite struct LineBufferTests {
    private func strings(_ lines: [Data]) -> [String] { lines.map { String(decoding: $0, as: UTF8.self) } }

    @Test func splitsCompleteLines() throws {
        var buffer = LineBuffer()
        #expect(strings(try buffer.append(Array("a\nbb\n".utf8))) == ["a", "bb"])
    }

    @Test func keepsPartialLineUntilNewline() throws {
        var buffer = LineBuffer()
        #expect(try buffer.append(Array("{\"id\":".utf8)).isEmpty)
        #expect(strings(try buffer.append(Array("1}\n{".utf8))) == ["{\"id\":1}"])
        #expect(strings(try buffer.append(Array("}\n".utf8))) == ["{}"])
    }

    @Test func dropsCarriageReturnsAndBlankLines() throws {
        var buffer = LineBuffer()
        #expect(strings(try buffer.append(Array("a\r\n\n\nb\n".utf8))) == ["a", "b"])
    }

    @Test func rejectsOverlongLine() {
        var buffer = LineBuffer(maxLineLength: 8)
        #expect(throws: HerdrError.lineTooLong) { try buffer.append(Array("0123456789".utf8)) }
    }
}

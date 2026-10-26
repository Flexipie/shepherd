import Foundation
import Testing
@testable import ReportKit

@Suite struct ReportFileTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000.25)

    @Test func roundTripKeepsEveryField() throws {
        let report = ReportFile(agent: "tmux:/tmp/sock:%3", status: .blocked, message: "Waiting", question: "Merge?",
                                kind: "claude", cwd: "/work/app", updatedAt: now)
        let decoded = try ReportFile.decode(report.encoded())
        #expect(decoded == report)
        #expect(decoded.version == ReportFile.currentVersion)
    }

    @Test func unknownKeysAreIgnoredAndOptionalKeysMayBeMissing() throws {
        let json = """
        {"version": 1, "agent": "demo", "status": "working", "updatedAt": "2027-01-15T10:00:00Z", "future": {"x": 1}}
        """
        let report = try ReportFile.decode(Data(json.utf8))
        #expect(report.agent == "demo")
        #expect(report.status == .working)
        #expect(report.message == nil)
        #expect(report.cwd == nil)
        #expect(report.updatedAt == ISO8601DateFormatter().date(from: "2027-01-15T10:00:00Z"))
    }

    @Test(arguments: [
        "not json",
        "[1, 2]",
        #"{"agent": "a", "status": "working", "updatedAt": "2027-01-15T10:00:00Z"}"#,
        #"{"version": 2, "agent": "a", "status": "working", "updatedAt": "2027-01-15T10:00:00Z"}"#,
        #"{"version": 1, "agent": "", "status": "working", "updatedAt": "2027-01-15T10:00:00Z"}"#,
        #"{"version": 1, "agent": "a", "status": "napping", "updatedAt": "2027-01-15T10:00:00Z"}"#,
        #"{"version": 1, "agent": "a", "status": "working"}"#,
        #"{"version": 1, "agent": "a", "status": "working", "updatedAt": "yesterday"}"#,
    ])
    func rejectsFilesItCannotUse(_ text: String) {
        #expect(throws: ReportProblem.self) { try ReportFile.decode(Data(text.utf8)) }
    }

    @Test func messagesAreCutAtTheByteLimitOnACharacterBoundary() {
        // Each "é" is two bytes, so 3000 of them are 6000 bytes; the cut must land on a whole character.
        let long = String(repeating: "é", count: 3000)
        let report = ReportFile(agent: "a", status: .working, message: long, updatedAt: now)
        #expect(report.message?.utf8.count == ReportFile.messageLimit)
        #expect(report.message == String(repeating: "é", count: 2048))
    }

    @Test func aShortMessageIsKeptWhole() {
        let report = ReportFile(agent: "a", status: .done, message: "all good", updatedAt: now)
        #expect(report.message == "all good")
    }
}

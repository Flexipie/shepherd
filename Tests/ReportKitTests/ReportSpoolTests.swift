import Foundation
import Testing
@testable import ReportKit

@Suite struct ReportSpoolTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// A fresh folder for one test, removed when the test's value goes away.
    final class Scratch {
        let url = FileManager.default.temporaryDirectory.appending(path: "report-spool-\(UUID().uuidString)")
        deinit { try? FileManager.default.removeItem(at: url) }
    }

    @Test func writeThenReadReturnsTheReport() throws {
        let scratch = Scratch()
        let spool = ReportSpool(directory: scratch.url)
        let report = ReportFile(agent: "demo", status: .working, message: "hi", updatedAt: now)
        try spool.write(report)
        let contents = try spool.read()
        #expect(contents.reports == [report])
        #expect(contents.problems.isEmpty)
    }

    @Test func aSecondWriteReplacesTheFileAndLeavesNoTemporaryFiles() throws {
        let scratch = Scratch()
        let spool = ReportSpool(directory: scratch.url)
        try spool.write(ReportFile(agent: "demo", status: .working, updatedAt: now))
        try spool.write(ReportFile(agent: "demo", status: .blocked, question: "Ship?", updatedAt: now))
        let names = try FileManager.default.contentsOfDirectory(atPath: scratch.url.path)
        #expect(names.count == 1)
        #expect(names.allSatisfy { $0.hasSuffix(".json") && !$0.hasPrefix(".") })
        let contents = try spool.read()
        #expect(contents.reports.map(\.status) == [.blocked])
        #expect(contents.reports.first?.question == "Ship?")
    }

    @Test func fileNamesAreTheSHA256OfTheAgentKey() {
        let spool = ReportSpool(directory: URL(fileURLWithPath: "/spool"))
        let name = spool.url(for: "demo").lastPathComponent
        // sha256("demo")
        #expect(name == "2a97516c354b68848cdbd8f54a226a0a55b21ed138e207ad6c5cbb9c00aa5aea.json")
    }

    @Test func removeDeletesTheFileAndAMissingFileIsNotAnError() throws {
        let scratch = Scratch()
        let spool = ReportSpool(directory: scratch.url)
        try spool.write(ReportFile(agent: "demo", status: .idle, updatedAt: now))
        try spool.remove(agent: "demo")
        #expect(try spool.read().reports.isEmpty)
        try spool.remove(agent: "demo")
    }

    @Test func aBadFileIsSkippedAndNamedAndTheGoodOnesStillRead() throws {
        let scratch = Scratch()
        let spool = ReportSpool(directory: scratch.url)
        try spool.write(ReportFile(agent: "good", status: .done, updatedAt: now))
        try Data("{not json".utf8).write(to: scratch.url.appending(path: "broken.json"))
        try Data("ignored".utf8).write(to: scratch.url.appending(path: "notes.txt"))
        let contents = try spool.read()
        #expect(contents.reports.map(\.agent) == ["good"])
        #expect(contents.problems.count == 1)
        #expect(contents.problems.first?.hasPrefix("broken.json") == true)
    }

    @Test func readCreatesAMissingFolder() throws {
        let scratch = Scratch()
        let contents = try ReportSpool(directory: scratch.url.appending(path: "nested")).read()
        #expect(contents.reports.isEmpty)
        #expect(FileManager.default.fileExists(atPath: scratch.url.appending(path: "nested").path))
    }

    @Test func theDirectoryComesFromTheEnvironmentOrTheAppFolder() {
        #expect(ReportSpool.directory(environment: ["SHEPHERD_SPOOL_DIR": "/tmp/spool"]).path == "/tmp/spool")
        #expect(ReportSpool.directory(environment: ["SHEPHERD_SPOOL_DIR": ""]).path.hasSuffix("Shepherd/reports"))
        #expect(ReportSpool.directory(environment: [:]).path.hasSuffix("Shepherd/reports"))
    }
}

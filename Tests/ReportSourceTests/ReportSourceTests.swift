import Foundation
import ReportKit
import ShepherdCore
import Testing
@testable import ReportSource

@MainActor
@Suite struct ReportSourceTests {
    final class Scratch {
        let url = FileManager.default.temporaryDirectory.appending(path: "report-source-\(UUID().uuidString)")
        deinit { try? FileManager.default.removeItem(at: url) }
    }

    /// Waits up to 3 s for `condition`, so a busy test run does not fail on timing.
    func until(_ condition: () -> Bool) async {
        for _ in 0..<300 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
    }

    func running(_ spool: ReportSpool) -> (HerdStore, ReportSource) {
        let source = ReportSource(spool: spool, debounce: .milliseconds(10))
        let store = HerdStore()
        store.add(source)
        store.start()
        return (store, source)
    }

    @Test func existingReportsAreTheBaselineAndAnnounceNothing() async {
        let scratch = Scratch()
        let spool = ReportSpool(directory: scratch.url)
        let now = Date()
        try? spool.write(ReportFile(agent: "old", status: .blocked, question: "Merge?", updatedAt: now))
        let (store, source) = running(spool)
        await until { store.agents.count == 1 }
        #expect(store.sourceStates[ReportSource.sourceID] == .live)
        #expect(store.agents.first?.status == .blocked)
        #expect(store.agents.first?.question == "Merge?")
        #expect(store.lastTransitions.isEmpty)
        await source.stop()
    }

    @Test func aReportWrittenIntoTheSpoolReachesTheHerd() async throws {
        let scratch = Scratch()
        let spool = ReportSpool(directory: scratch.url)
        let (store, source) = running(spool)
        await until { store.sourceStates[ReportSource.sourceID] == .live }

        try spool.write(ReportFile(agent: "fresh", status: .blocked, question: "Ship?", kind: "claude",
                                   cwd: "/work/app", updatedAt: Date()))
        await until { store.agents.count == 1 }
        let agent = try #require(store.agents.first)
        #expect(agent.id == AgentID(source: "report", local: "fresh"))
        #expect(agent.status == .blocked)
        #expect(store.needsYou.map(\.id) == [agent.id])
        #expect(store.lastTransitions.map(\.from) == [nil])
        #expect(store.lastTransitions.map(\.to) == [.blocked])

        try spool.remove(agent: "fresh")
        await until { store.agents.isEmpty }
        #expect(store.agents.isEmpty)
        #expect(store.lastTransitions.first?.to == nil)
        await source.stop()
    }

    @Test func aWorkingReportGoesUnknownOnItsOwnWhenItGoesQuiet() async throws {
        let scratch = Scratch()
        let spool = ReportSpool(directory: scratch.url)
        let (store, source) = running(spool)
        await until { store.sourceStates[ReportSource.sourceID] == .live }

        // Quiet in 0.4 s: the one-shot timer should re-read without any file changing.
        try spool.write(ReportFile(agent: "build", status: .working, updatedAt: Date().addingTimeInterval(-ReportTracker.quietLimit + 0.4)))
        await until { store.agents.first?.status == .unknown }
        #expect(store.agents.first?.status == .unknown)
        #expect(store.lastTransitions.first?.to == .unknown)
        await source.stop()
    }

    @Test func aStoppedSourceEndsItsUpdates() async {
        let scratch = Scratch()
        let source = ReportSource(spool: ReportSpool(directory: scratch.url), debounce: .milliseconds(10))
        source.start()
        await source.stop()
        var received = 0
        for await _ in source.updates { received += 1 }
        #expect(received <= 1)
    }
}

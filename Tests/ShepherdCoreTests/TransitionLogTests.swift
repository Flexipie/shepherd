import Foundation
import Testing
@testable import ShepherdCore

@Suite struct TransitionLogTests {
    func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "shepherd-log-\(UUID().uuidString)/transitions.jsonl")
    }

    func transition(_ local: String, _ to: HerdStatus, at seconds: Double, marker: String? = nil) -> HerdTransition {
        HerdTransition(agent: AgentID(source: "herdr", local: local), kind: "claude", project: "project \(local)",
                       from: .working, to: to, at: Date(timeIntervalSince1970: seconds), marker: marker)
    }

    @Test func appendsAndReloadsInOrder() async {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let log = TransitionLog(url: url)
        await log.append([transition("a", .done, at: 1)])
        await log.append([transition("b", .blocked, at: 2), transition("a", .working, at: 3)])
        let reloaded = await TransitionLog(url: url).load()
        #expect(reloaded.map(\.agent.local) == ["a", "b", "a"])
        #expect(reloaded.first?.project == "project a")
        #expect(await log.latestByAgent()[AgentID(source: "herdr", local: "a")]?.to == .working)
    }

    @Test func skipsUnreadableLines() async throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let log = TransitionLog(url: url)
        await log.append([transition("a", .done, at: 1)])
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{not json\n".utf8))
        try handle.close()
        await log.append([transition("b", .done, at: 2)])
        #expect(await TransitionLog(url: url).load().map(\.agent.local) == ["a", "b"])
    }

    @Test func compactsToTheNewestEntries() async {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let log = TransitionLog(url: url, capacity: 10)
        for index in 0..<25 { await log.append([transition("a\(index)", .done, at: Double(index))]) }
        let kept = await TransitionLog(url: url).load()
        #expect(kept.count <= 20)
        #expect(kept.last?.agent.local == "a24")
        #expect(kept.count >= 10)
    }

    @Test func missingFileIsEmpty() async {
        #expect(await TransitionLog(url: tempURL()).load().isEmpty)
    }
}

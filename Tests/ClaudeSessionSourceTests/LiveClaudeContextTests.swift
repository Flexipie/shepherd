import Foundation
import HerdrKit
import Testing
@testable import ClaudeSessionSource
@testable import HerdrSource
@testable import ShepherdCore

/// Reads the context size of every live Claude agent through the herdr on this machine.
/// Skipped unless `SHEPHERD_LIVE=1`; prints only pane ids and numbers.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["SHEPHERD_LIVE"] == "1"))
struct LiveClaudeContextTests {
    @Test func everyClaudeAgentHasAContextSize() async throws {
        let snapshot = try await HerdrClient().snapshot()
        let reader = ClaudeContextReader()
        var found = 0
        for agent in snapshot.agents {
            guard let session = HerdrSource.session(agent), session.kind == "claude" else { continue }
            let started = Date()
            let tokens = try await reader.contextTokens(for: session)
            let ms = Int(Date().timeIntervalSince(started) * 1000)
            print("pane \(agent.id): \(tokens.map(String.init) ?? "none") tokens, \(ms) ms")
            if tokens != nil { found += 1 }
        }
        print("\(found) Claude agents with a context size")
    }
}

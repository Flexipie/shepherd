import Darwin
import Foundation
@testable import ShepherdCore

/// A source the test drives by hand.
@MainActor
final class StubSource: AgentSource {
    let id: SourceID
    var displayName: String { id.rawValue }
    var capabilities: SourceCapabilities = [.focus]
    let updates: AsyncStream<SourceUpdate>
    private let continuation: AsyncStream<SourceUpdate>.Continuation
    private(set) var focused: [AgentID] = []
    var hostPIDs: [pid_t] = []

    init(_ id: SourceID) {
        self.id = id
        (updates, continuation) = AsyncStream.makeStream()
    }

    func start() {}
    func stop() async { continuation.finish() }
    func focus(_ agent: AgentID) async throws { focused.append(agent) }
    func hostApplicationPIDs() -> [pid_t] { hostPIDs }
    func send(_ update: SourceUpdate) { continuation.yield(update) }
}

func herdAgent(_ source: SourceID, _ local: String, _ status: HerdStatus, since: Date? = nil,
               focused: Bool = false, project: String = "project 1") -> HerdAgent {
    HerdAgent(id: AgentID(source: source, local: local), kind: "claude", name: "agent \(local)", project: project,
              status: status, since: since.map { Since($0, .exact) }, isFocusedInSource: focused)
}

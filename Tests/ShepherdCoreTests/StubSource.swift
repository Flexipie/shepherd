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
    private(set) var focusedProjects: [ProjectID] = []
    var hostPIDs: [pid_t] = []

    init(_ id: SourceID) {
        self.id = id
        (updates, continuation) = AsyncStream.makeStream()
    }

    func start() {}
    func stop() async { continuation.finish() }
    func focus(_ agent: AgentID) async throws { focused.append(agent) }
    func focusProject(_ project: ProjectID) async throws { focusedProjects.append(project) }
    func hostApplicationPIDs() -> [pid_t] { hostPIDs }
    func send(_ update: SourceUpdate) { continuation.yield(update) }
}

func herdAgent(_ source: SourceID, _ local: String, _ status: HerdStatus, since: Date? = nil,
               focused: Bool = false, project: String = "project 1", projectID: String = "p1",
               tokens: [String: String] = [:]) -> HerdAgent {
    HerdAgent(id: AgentID(source: source, local: local), kind: "claude", name: "agent \(local)",
              projectID: ProjectID(source: source, local: projectID), project: project,
              status: status, since: since.map { Since($0, .exact) }, tokens: tokens, isFocusedInSource: focused)
}

func herdProject(_ source: SourceID, _ local: String, name: String? = nil, tokens: [String: String] = [:]) -> HerdProject {
    HerdProject(id: ProjectID(source: source, local: local), name: name ?? "project \(local)", tokens: tokens)
}

import Foundation
import HerdrFake
import ShepherdCore
import TmuxSource

/// Demo mode's tmux agents: what agents read from terminal screens look like (labelled inferred,
/// no focus, no new tasks), without a tmux server. It never runs tmux. Answering the waiting agent
/// sets it working, as the fake herdr does.
@MainActor
final class DemoScreenSource: AgentSource {
    let id = TmuxSource.sourceID
    let displayName = "tmux"
    let capabilities: SourceCapabilities = [.readOutput, .sendKeys, .sendText]
    let updates: AsyncStream<SourceUpdate>

    private let continuation: AsyncStream<SourceUpdate>.Continuation
    private static let folder = "/tmp/cli"
    private let project = HerdProject(id: ProjectID(source: TmuxSource.sourceID, local: folder), name: "cli",
                                      path: folder, isInferred: true)
    private var agents: [String: (kind: String, status: HerdStatus, since: Date)]

    init(now: Date = .now) {
        agents = ["tmux:demo:%1": ("claude", .blocked, now), "tmux:demo:%2": ("codex", .working, now)]
        (updates, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(16))
    }

    func start() { publish() }

    func stop() async { continuation.finish() }

    func focus(_ agent: AgentID) async throws {
        throw AgentSourceError.unsupported(.focus)
    }

    func read(_ agent: AgentID, lines: Int) async throws -> String {
        let entry = try entry(agent)
        return FakeScreens.screen(kind: entry.kind, status: entry.status.rawValue)
    }

    /// A choice or Return answers the question; Escape turns it down.
    func sendKeys(_ agent: AgentID, _ keys: [String]) async throws {
        guard try entry(agent).status == .blocked, let last = keys.last?.lowercased() else { return }
        if last == "esc" || last == "escape" {
            set(agent, .idle)
        } else if last == "enter" || last == "return" || last.allSatisfy(\.isNumber) {
            set(agent, .working)
        }
    }

    func sendText(_ agent: AgentID, _ text: String) async throws {
        _ = try entry(agent)
        set(agent, .working)
    }

    func hostApplicationPIDs() -> [pid_t] { [] }

    private func entry(_ agent: AgentID) throws -> (kind: String, status: HerdStatus, since: Date) {
        guard let entry = agents[agent.local] else { throw AgentSourceError.failed("no such demo agent") }
        return entry
    }

    private func set(_ agent: AgentID, _ status: HerdStatus) {
        guard let old = agents[agent.local], old.status != status else { return }
        let now = Date.now
        agents[agent.local] = (old.kind, status, now)
        publish([HerdTransition(agent: agent, kind: old.kind, project: project.name, from: old.status, to: status, at: now)])
    }

    private func publish(_ transitions: [HerdTransition] = []) {
        let herd = agents.keys.sorted().map { key in
            let entry = agents[key]!
            return HerdAgent(id: AgentID(source: id, local: key), kind: entry.kind, name: entry.kind, projectID: project.id,
                             project: project.name, status: entry.status, since: Since(entry.since, .exact),
                             cwd: Self.folder, isInferred: true)
        }
        continuation.yield(SourceUpdate(agents: herd, projects: [project], state: .live, transitions: transitions))
    }
}

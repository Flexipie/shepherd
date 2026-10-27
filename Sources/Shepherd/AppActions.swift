import AppKit
import ShepherdCore

/// Jumps to agents through the store, and keeps `Presence` current by watching which app is
/// frontmost.
@MainActor
final class AppActions: AgentActions {
    private let store: HerdStore
    private let presence: Presence
    private var observer: NSObjectProtocol?
    /// Where the "next" hotkey went last, so repeated presses walk the queue.
    private var lastNext: AgentID?

    private let config: ConfigStore

    init(store: HerdStore, presence: Presence, config: ConfigStore) {
        self.store = store
        self.presence = presence
        self.config = config
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updatePresence() }
        }
    }

    /// A source that tried and could not show the agent (tmux with no terminal attached) says why
    /// in an alert; otherwise the jump would do nothing at all.
    func jump(to agent: AgentID) {
        Task {
            do {
                try await store.focus(agent)
            } catch AgentSourceError.failed(let reason) {
                Self.alert("Cannot show the agent", reason)
            } catch {}
        }
    }

    private static func alert(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        NSApp.activate()
        alert.runModal()
    }

    /// Jumps to the next waiting agent; with nothing waiting, does nothing.
    func jumpToNext() {
        updatePresence()
        guard let agent = NextInQueue.pick(store: store, presence: presence, after: lastNext) else { return }
        lastNext = agent.id
        jump(to: agent.id)
    }

    func focusProject(_ project: ProjectID) {
        Task { try? await store.focusProject(project) }
    }

    func capabilities(of agent: AgentID) -> SourceCapabilities {
        store.capabilities(of: agent)
    }

    func read(_ agent: AgentID, lines: Int) async throws -> String {
        try await store.read(agent, lines: lines)
    }

    func sendKeys(_ agent: AgentID, _ keys: [String]) async throws {
        try await store.sendKeys(agent, keys)
    }

    func sendText(_ agent: AgentID, _ text: String) async throws {
        try await store.sendText(agent, text)
    }

    func prompt(_ agent: AgentID, _ text: String) async throws {
        try await store.prompt(agent, text)
    }

    func startTask(_ task: NewTask) async throws -> AgentID {
        try await store.startTask(task, args: config.config.agents[task.kind]?.args ?? [])
    }

    func updatePresence() {
        guard let front = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return }
        let frontmost = Set(store.sources.filter { $0.hostApplicationPIDs().contains(front) }.map(\.id))
        if presence.frontmostSources != frontmost { presence.frontmostSources = frontmost }
    }
}

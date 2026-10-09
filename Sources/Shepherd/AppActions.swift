import AppKit
import ShepherdCore

/// Jumps to agents through the store, and keeps `Presence` current by watching which app is
/// frontmost.
@MainActor
final class AppActions: AgentActions {
    private let store: HerdStore
    private let presence: Presence
    private var observer: NSObjectProtocol?

    init(store: HerdStore, presence: Presence) {
        self.store = store
        self.presence = presence
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updatePresence() }
        }
    }

    func jump(to agent: AgentID) {
        Task { try? await store.focus(agent) }
    }

    func focusProject(_ project: ProjectID) {
        Task { try? await store.focusProject(project) }
    }

    func updatePresence() {
        guard let front = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return }
        let frontmost = Set(store.sources.filter { $0.hostApplicationPIDs().contains(front) }.map(\.id))
        if presence.frontmostSources != frontmost { presence.frontmostSources = frontmost }
    }
}

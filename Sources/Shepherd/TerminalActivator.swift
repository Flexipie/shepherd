import AppKit
import HerdrKit
import ShepherdCore

/// Jumps to an agent (herdr focus, then the hosting terminal forward) and keeps `Presence`
/// current by watching which app is frontmost.
@MainActor
final class TerminalActivator: AgentActions {
    private let store: SessionStore
    private let presence: Presence
    private var observer: NSObjectProtocol?

    init(store: SessionStore, presence: Presence) {
        self.store = store
        self.presence = presence
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updatePresence() }
        }
        updatePresence()
    }

    func jump(to paneID: String) {
        Task {
            try? await store.focus(paneID: paneID)
            activateTerminal()
        }
    }

    /// The apps hosting an attached herdr client.
    private func terminalApps() -> [NSRunningApplication] {
        let hosts = TerminalLocator.hostingApps(
            of: TerminalLocator.pids(named: "herdr"),
            parent: TerminalLocator.parent(of:),
            isApp: { NSRunningApplication(processIdentifier: $0)?.activationPolicy == .regular })
        return hosts.compactMap { NSRunningApplication(processIdentifier: $0) }
    }

    private func activateTerminal() {
        guard let terminal = terminalApps().first else { return }
        NSApp.yieldActivation(to: terminal)
        terminal.activate()
    }

    private func updatePresence() {
        guard let front = NSWorkspace.shared.frontmostApplication else { return }
        let frontmost = terminalApps().contains { $0.processIdentifier == front.processIdentifier }
        if presence.terminalIsFrontmost != frontmost { presence.terminalIsFrontmost = frontmost }
    }
}

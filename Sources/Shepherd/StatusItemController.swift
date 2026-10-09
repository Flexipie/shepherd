import AppKit
import Observation
import ShepherdCore

/// The menu bar item. The button redraws only when a module's status contribution changes; the
/// menu is built when it opens, so nothing renders while it is closed.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let store: HerdStore
    private let modules: [any ShepherdModule]
    private let actions: any AgentActions

    init(store: HerdStore, modules: [any ShepherdModule], actions: any AgentActions) {
        self.store = store
        self.modules = modules
        self.actions = actions
        super.init()
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        render()
    }

    private func render() {
        let contribution = withObservationTracking {
            modules.lazy.compactMap(\.status).first
        } onChange: { [weak self] in
            Task { @MainActor in self?.render() }
        }
        apply(contribution)
    }

    private func apply(_ contribution: StatusContribution?) {
        guard let button = item.button else { return }
        let contribution = contribution ?? StatusContribution(symbol: "pawprint", accessibilityLabel: "Shepherd")
        let image = NSImage(systemSymbolName: contribution.symbol, accessibilityDescription: contribution.accessibilityLabel)
        image?.isTemplate = true
        button.image = image
        button.imagePosition = .imageLeading
        button.title = contribution.count.map { " \($0)" } ?? ""
        button.appearsDisabled = contribution.emphasis == .dimmed
        button.setAccessibilityLabel(contribution.accessibilityLabel)
        button.toolTip = contribution.accessibilityLabel
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        for line in headerLines() {
            menu.addItem(NSMenuItem(title: line, action: nil, keyEquivalent: ""))
        }

        let waiting = store.needsYou.filter { store.sourceStates[$0.id.source]?.isLive == true }
        if !waiting.isEmpty {
            menu.addItem(.separator())
            menu.addItem(NSMenuItem.sectionHeader(title: "Needs you"))
            let now = Date()
            for agent in waiting {
                let reason = agent.status == .blocked ? "needs you" : "finished"
                let elapsed = Elapsed.short(agent.since, now: now).map { ", \($0)" } ?? ""
                let project = agent.project.isEmpty ? "" : " · \(agent.project)"
                let entry = NSMenuItem(title: "\(agent.name)\(project): \(agent.statusLabel ?? reason)\(elapsed)",
                                       action: #selector(jump(_:)), keyEquivalent: "")
                entry.target = self
                entry.representedObject = agent.id
                entry.image = NSImage(systemSymbolName: agent.status == .blocked ? "exclamationmark.circle" : "checkmark.circle",
                                      accessibilityDescription: reason)
                menu.addItem(entry)
            }
        }

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Shepherd", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    /// The herd's state, then each source's own lines (version, warnings).
    private func headerLines() -> [String] {
        var lines: [String]
        switch store.overallState {
        case .connecting: lines = ["Connecting…"]
        case .disconnected(let reason): lines = ["Not connected: \(reason). Retrying."]
        case .stale(let reason): lines = ["Reconnecting: \(reason)"]
        case .live: lines = ["\(store.workingCount) working, \(store.needsYou.count) waiting"]
        }
        for source in store.sources {
            lines += store.statusLines[source.id] ?? []
        }
        return lines
    }

    @objc private func jump(_ sender: NSMenuItem) {
        guard let agent = sender.representedObject as? AgentID else { return }
        actions.jump(to: agent)
    }
}

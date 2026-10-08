import AppKit
import HerdrKit
import Observation
import ShepherdCore

/// The menu bar item. The button redraws only when a module's status contribution changes; the
/// menu is built when it opens, so nothing renders while it is closed.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let store: SessionStore
    private let modules: [any ShepherdModule]
    private let actions: any AgentActions

    init(store: SessionStore, modules: [any ShepherdModule], actions: any AgentActions) {
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

        let waiting = store.connection.isLive ? store.needsYou : []
        if !waiting.isEmpty {
            menu.addItem(.separator())
            menu.addItem(NSMenuItem.sectionHeader(title: "Needs you"))
            let now = Date()
            for agent in waiting {
                let reason = agent.status == .blocked ? "needs you" : "finished"
                let elapsed = Elapsed.short(agent.since, now: now).map { ", \($0)" } ?? ""
                let workspace = agent.workspaceLabel.isEmpty ? "" : " · \(agent.workspaceLabel)"
                let entry = NSMenuItem(title: "\(agent.agent.displayName)\(workspace): \(reason)\(elapsed)",
                                       action: #selector(jump(_:)), keyEquivalent: "")
                entry.target = self
                entry.representedObject = agent.id
                entry.image = NSImage(systemSymbolName: agent.status == .blocked ? "exclamationmark.circle" : "checkmark.circle",
                                      accessibilityDescription: reason)
                menu.addItem(entry)
            }
        }

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Socket: \(store.client.socketPath)", action: nil, keyEquivalent: ""))
        let quit = NSMenuItem(title: "Quit Shepherd", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    private func headerLines() -> [String] {
        let snapshot = store.session.snapshot
        var lines: [String]
        switch store.connection {
        case .connecting: lines = ["Connecting to herdr…"]
        case .disconnected(let reason): lines = ["Not connected: \(reason). Retrying."]
        case .stale(let reason): lines = ["Reconnecting: \(reason)"]
        case .live:
            let working = store.workingCount
            lines = ["herdr \(snapshot.version): \(working) working, \(store.needsYou.count) waiting"]
        }
        switch store.compatibility {
        case .matched: break
        case .older(let value): lines.append("herdr protocol \(value) is older than tested (\(HerdrProtocol.tested))")
        case .newer(let value): lines.append("herdr protocol \(value) is newer than tested (\(HerdrProtocol.tested))")
        }
        return lines
    }

    @objc private func jump(_ sender: NSMenuItem) {
        guard let paneID = sender.representedObject as? String else { return }
        actions.jump(to: paneID)
    }
}

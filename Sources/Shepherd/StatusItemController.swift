import AppKit
import Observation
import ShepherdCore

/// The menu bar item. The button redraws only when a module's status contribution changes. A
/// left click toggles the panel; a right or control click shows a small menu, built when it
/// opens, so nothing renders while it is closed.
@MainActor
final class StatusItemController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let store: HerdStore
    private let registry: ModuleRegistry
    private let panel: PanelController

    init(store: HerdStore, registry: ModuleRegistry, panel: PanelController) {
        self.store = store
        self.registry = registry
        self.panel = panel
        super.init()
        // No permanent `item.menu`: while one is set, the button's action never fires.
        item.button?.target = self
        item.button?.action = #selector(clicked(_:))
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        panel.onVisibilityChange = { [weak self] open in
            // After the click's own highlight handling, so it sticks.
            Task { @MainActor in self?.item.button?.highlight(open) }
        }
        render()
    }

    private func render() {
        let contribution = withObservationTracking {
            registry.modules.lazy.compactMap(\.status).first
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

    @objc private func clicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            panel.close()
            showMenu()
        } else {
            togglePanel()
        }
    }

    func togglePanel() {
        if panel.isOpen {
            panel.close()
            return
        }
        // A click on the button first takes key from the panel, which closes it; that click must
        // not reopen it.
        guard Date().timeIntervalSince(panel.closedAt) > 0.3 else { return }
        guard let button = item.button, let window = button.window, let screen = window.screen ?? NSScreen.main else { return }
        panel.open(under: window.convertToScreen(button.convert(button.bounds, to: nil)), on: screen)
    }

    // MARK: Menu

    private func showMenu() {
        let menu = NSMenu()
        for line in HerdSummary.lines(store) {
            menu.addItem(NSMenuItem(title: line, action: nil, keyEquivalent: ""))
        }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Shepherd", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }
}

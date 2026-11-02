import AppKit
import Observation
import ShepherdCore

/// The menu bar item. The button redraws only when a module's status contribution changes. A
/// left click toggles the palette; a right or control click shows a small menu, built when it
/// opens, so nothing renders while it is closed.
@MainActor
final class StatusItemController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let store: HerdStore
    private let registry: ModuleRegistry
    private let palette: PaletteController
    private let isDemo: Bool
    /// The title of the menu's demo item, read when the menu opens; nil for none.
    private let demoItem: () -> String?
    private let switchDemo: () -> Void

    init(store: HerdStore, registry: ModuleRegistry, palette: PaletteController, isDemo: Bool, demoItem: @escaping () -> String?,
         switchDemo: @escaping () -> Void) {
        self.store = store
        self.registry = registry
        self.palette = palette
        self.isDemo = isDemo
        self.demoItem = demoItem
        self.switchDemo = switchDemo
        super.init()
        // No permanent `item.menu`: while one is set, the button's action never fires.
        item.button?.target = self
        item.button?.action = #selector(clicked(_:))
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
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
        var contribution = contribution ?? StatusContribution(symbol: "pawprint", accessibilityLabel: "Shepherd")
        if isDemo {
            contribution = StatusContribution(symbol: contribution.symbol, count: contribution.count, emphasis: contribution.emphasis,
                                              accessibilityLabel: "Demo. " + contribution.accessibilityLabel)
        }
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
            palette.close()
            showMenu()
        } else {
            togglePalette()
        }
    }

    private func togglePalette() {
        if palette.isOpen {
            palette.close()
            return
        }
        // A click on the button first takes key from the palette, which closes it; that click must
        // not reopen it.
        guard Date().timeIntervalSince(palette.closedAt) > 0.3 else { return }
        palette.open()
    }

    // MARK: Menu

    private func showMenu() {
        let menu = NSMenu()
        if isDemo { menu.addItem(NSMenuItem(title: "Demo: these agents are made up", action: nil, keyEquivalent: "")) }
        for line in HerdSummary.lines(store) {
            menu.addItem(NSMenuItem(title: line, action: nil, keyEquivalent: ""))
        }
        menu.addItem(.separator())
        if let title = demoItem() {
            let item = NSMenuItem(title: title, action: #selector(demoChosen), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        menu.addItem(NSMenuItem(title: "Quit Shepherd", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }

    @objc private func demoChosen() {
        switchDemo()
    }
}

import AppKit
import Observation
import ShepherdCore
import ShepherdUI
import SwiftUI

/// Opens and closes the palette: centred in the upper third of the screen under the mouse, over
/// any app, without activating Shepherd. A fresh view each opening, so the query starts empty.
/// It closes on Escape, a click outside, a Space change, losing key, or after an action. It does
/// not count as a visible panel: it shows no gadgets, so nothing starts reading for it.
@MainActor
final class PaletteController: NSObject, NSWindowDelegate {
    private let context: ModuleContext
    private let registry: ModuleRegistry
    private let actions: AppActions
    private let host = FloatingPanelHost()
    private var panel: ShepherdPanel?
    private var hosting: PanelHostingView<PaletteView>?
    private var screen: NSScreen?
    /// Where the top edge sits, fixed for the opening so the palette grows downwards.
    private var top: CGFloat = 0
    /// Bumps on every open, so a stale observation callback from an earlier opening is ignored.
    private var generation = 0

    var isOpen: Bool { panel != nil }

    init(context: ModuleContext, registry: ModuleRegistry, actions: AppActions) {
        self.context = context
        self.registry = registry
        self.actions = actions
    }

    func toggle() {
        if isOpen { close() } else { open() }
    }

    func open() {
        guard panel == nil, let screen = FloatingPanelHost.mouseScreen else { return }
        self.screen = screen
        top = screen.visibleFrame.maxY - screen.visibleFrame.height * 0.22
        generation += 1
        let panel = ShepherdPanel()
        panel.delegate = self
        panel.onCancel = { [weak self] in self?.close() }
        let hosting = PanelHostingView(rootView: view(content()))
        hosting.sizingOptions = [.intrinsicContentSize]
        hosting.onSizeChange = { [weak self] in
            // Resize after SwiftUI finishes the pass that changed the size.
            Task { @MainActor in self?.layout() }
        }
        panel.contentView = FloatingPanelHost.glass(hosting, cornerRadius: 18)
        self.panel = panel
        self.hosting = hosting
        layout()
        panel.makeKeyAndOrderFront(nil)
        host.startMonitoring { [weak self] in self?.close() }
        render(generation)
    }

    func close() {
        guard let panel else { return }
        host.stopMonitoring()
        panel.delegate = nil
        panel.orderOut(nil)
        panel.contentView = nil
        self.panel = nil
        hosting = nil
    }

    // MARK: Content

    private func content() -> PaletteContent {
        let store = context.store
        return PaletteContent(items: PaletteIndex.items(context: context, modules: registry.modules),
                              notice: store.overallState.isLive ? nil : HerdSummary.lines(store).first)
    }

    private func view(_ content: PaletteContent) -> PaletteView {
        PaletteView(content: content, maxListHeight: maxListHeight) { [weak self] action in
            self?.perform(action)
        }
    }

    /// Re-renders when anything the content reads changes, for as long as this opening lasts.
    private func render(_ opening: Int) {
        guard opening == generation, let hosting else { return }
        let content = withObservationTracking {
            self.content()
        } onChange: { [weak self] in
            Task { @MainActor in self?.render(opening) }
        }
        hosting.rootView = view(content)
    }

    private func perform(_ action: PaletteAction) {
        close()
        switch action {
        case .jump(let agent): actions.jump(to: agent)
        case .focusProject(let project): actions.focusProject(project)
        case .nextInQueue: actions.jumpToNext()
        }
    }

    // MARK: Layout

    /// About nine agent rows, and never past the bottom of the screen.
    private var maxListHeight: CGFloat {
        min(9 * 44, ((screen ?? NSScreen.main)?.visibleFrame.height ?? 800) * 0.6)
    }

    private func layout() {
        guard let panel, let hosting, let screen else { return }
        let visible = screen.visibleFrame
        let width = PaletteView.width
        let height = min(hosting.fittingSize.height, top - visible.minY - 8)
        let x = visible.midX - width / 2
        panel.setFrame(NSRect(x: x, y: top - height, width: width, height: height), display: true)
    }

    func windowDidResignKey(_ notification: Notification) {
        close()
    }
}

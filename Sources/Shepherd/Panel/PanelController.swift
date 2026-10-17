import AppKit
import Observation
import ShepherdCore
import ShepherdUI
import SwiftUI

/// Opens and closes the panel under the status item. The window and its views exist only while
/// it is open; closed, nothing renders and nothing ticks. It closes on Escape, a click outside,
/// a Space change, or after a jump.
@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    private let content: PanelContentSource
    private let actions: any AgentActions
    private let presence: Presence
    private var panel: ShepherdPanel?
    private var hosting: PanelHostingView<PanelView>?
    private var anchor: NSRect = .zero
    private var screen: NSScreen?
    /// The tab shown. Each opening starts on Agents; the tab is not saved.
    private var tab: PanelTab = .agents
    private let host = FloatingPanelHost()
    /// Bumps on every open, so a stale observation callback from an earlier opening is ignored.
    private var generation = 0
    private(set) var closedAt = Date.distantPast
    var onVisibilityChange: ((Bool) -> Void)?

    var isOpen: Bool { panel != nil }

    init(content: PanelContentSource, actions: any AgentActions, presence: Presence) {
        self.content = content
        self.actions = actions
        self.presence = presence
    }

    /// Opens under `anchor` (a rect in screen coordinates, the status item button) on `screen`.
    func open(under anchor: NSRect, on screen: NSScreen) {
        guard panel == nil else { return }
        self.anchor = anchor
        self.screen = screen
        tab = .agents
        generation += 1
        let panel = ShepherdPanel()
        panel.delegate = self
        panel.onCancel = { [weak self] in self?.close() }
        let hosting = PanelHostingView(rootView: view(content.current()))
        hosting.sizingOptions = [.intrinsicContentSize]
        hosting.onSizeChange = { [weak self] in
            // Resize after SwiftUI finishes the pass that changed the size.
            Task { @MainActor in self?.layout() }
        }
        panel.contentView = FloatingPanelHost.glass(hosting, cornerRadius: 16)
        self.panel = panel
        self.hosting = hosting
        layout()
        panel.makeKeyAndOrderFront(nil)
        host.startMonitoring { [weak self] in self?.close() }
        render(generation)
        presence.setPanel("menu", showing: tab)
        onVisibilityChange?(true)
    }

    func close() {
        guard let panel else { return }
        host.stopMonitoring()
        panel.delegate = nil
        panel.orderOut(nil)
        panel.contentView = nil
        self.panel = nil
        hosting = nil
        closedAt = Date()
        presence.setPanel("menu", showing: nil)
        onVisibilityChange?(false)
    }

    // MARK: Content

    private func view(_ content: PanelContent) -> PanelView {
        PanelView(content: content, maxHeight: maxSectionsHeight, tab: tab, onTab: { [weak self] tab in
            self?.show(tab)
        }) { [weak self] action in
            self?.perform(action)
        }
    }

    private func show(_ tab: PanelTab) {
        guard let hosting, tab != self.tab else { return }
        self.tab = tab
        presence.setPanel("menu", showing: tab)
        hosting.rootView = view(content.current())
    }

    /// Re-renders when anything the content reads changes, for as long as this opening lasts.
    private func render(_ opening: Int) {
        guard opening == generation, let hosting else { return }
        let content = withObservationTracking {
            self.content.current()
        } onChange: { [weak self] in
            Task { @MainActor in self?.render(opening) }
        }
        hosting.rootView = view(content)
    }

    private func perform(_ action: PanelAction) {
        close()
        actions.perform(action)
    }

    // MARK: Layout

    /// Sections scroll past 70% of the screen, less room for the footer.
    private var maxSectionsHeight: CGFloat {
        ((screen ?? NSScreen.main)?.visibleFrame.height ?? 800) * 0.7 - 80
    }

    private func layout() {
        guard let panel, let hosting, let screen else { return }
        let size = hosting.fittingSize
        let visible = screen.visibleFrame
        let width = PanelView.width
        let height = min(size.height, visible.height - 8)
        var x = anchor.midX - width / 2
        x = min(max(x, visible.minX + 6), visible.maxX - width - 6)
        let top = min(anchor.minY - 5, visible.maxY)
        panel.setFrame(NSRect(x: x, y: top - height, width: width, height: height), display: true)
    }

    // MARK: Closing

    func windowDidResignKey(_ notification: Notification) {
        close()
    }
}

import AppKit
import Observation
import ShepherdCore
import ShepherdUI
import SwiftUI

/// Shows the first notch item any module offers. The panel and its views exist only while there
/// is something to show; when the item goes away they are torn down.
@MainActor
final class NotchController {
    private let registry: ModuleRegistry
    private let actions: any AgentActions
    private var panel: NotchPanel?
    private var hosting: NSHostingView<NotchPillView>?
    private var current: NotchItem?
    private var screenObserver: NSObjectProtocol?

    init(registry: ModuleRegistry, actions: any AgentActions) {
        self.registry = registry
        self.actions = actions
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.layout() }
        }
        render()
    }

    private func render() {
        let item = withObservationTracking {
            registry.modules.lazy.compactMap(\.notch).first
        } onChange: { [weak self] in
            Task { @MainActor in self?.render() }
        }
        guard item != current else { return }
        current = item
        if let item { show(item) } else { hide() }
    }

    private func show(_ item: NotchItem) {
        guard let geometry = NotchGeometry.current() else { return }
        let view = NotchPillView(item: item, style: geometry.style) { [weak self] in
            self?.actions.jump(to: item.agent.id)
        }
        if let hosting {
            hosting.rootView = view
        } else {
            let panel = NotchPanel()
            let hosting = NSHostingView(rootView: view)
            panel.contentView = hosting
            self.panel = panel
            self.hosting = hosting
            panel.setFrame(geometry.frame, display: false)
            fadeIn(panel)
        }
        layout()
    }

    private func hide() {
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel = nil
        hosting = nil
    }

    private func layout() {
        guard let panel, let geometry = NotchGeometry.current() else { return }
        panel.setFrame(geometry.frame, display: true)
    }

    private func fadeIn(_ panel: NotchPanel) {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            panel.orderFrontRegardless()
            return
        }
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            panel.animator().alphaValue = 1
        }
    }
}

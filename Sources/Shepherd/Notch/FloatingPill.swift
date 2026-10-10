import AppKit
import ShepherdCore
import ShepherdUI
import SwiftUI

/// The pill on a display without a notch: a capsule under the menu bar while a notch item is
/// offered. The window exists only while it shows.
@MainActor
final class FloatingPill {
    private var panel: NotchPanel?
    private var hosting: NSHostingView<NotchPillView>?

    func show(_ item: NotchItem, in frame: NSRect, onJump: @escaping () -> Void) {
        let view = NotchPillView(item: item, onJump: onJump)
        if let hosting {
            hosting.rootView = view
            panel?.setFrame(frame, display: true)
            return
        }
        let panel = NotchPanel()
        let hosting = NSHostingView(rootView: view)
        panel.contentView = hosting
        panel.setFrame(frame, display: false)
        self.panel = panel
        self.hosting = hosting
        fadeIn(panel)
    }

    func hide() {
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel = nil
        hosting = nil
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

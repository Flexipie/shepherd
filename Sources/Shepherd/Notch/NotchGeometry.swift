import AppKit
import ShepherdUI

/// Where the notch surface goes. On a notched display it is drawn around the notch, flush with
/// the top of the screen; `metrics` place each state relative to the notch. Elsewhere there is no
/// ear and no hover panel, only the pill as a small floating capsule under the menu bar.
struct NotchGeometry: Equatable {
    /// nil on a display without a notch.
    let metrics: NotchMetrics?
    /// The notch's top-left corner, in screen coordinates.
    let notchOrigin: NSPoint
    /// The floating pill's frame on a display without a notch.
    let floatingFrame: NSRect

    static let floatingWidth: CGFloat = 340
    /// Room the panel's footer needs below its scrolling sections.
    static let footerAllowance: CGFloat = 80

    /// The display with a notch if there is one, otherwise the main display.
    @MainActor
    static func current() -> NotchGeometry? {
        let notched = NSScreen.screens.first { $0.safeAreaInsets.top > 0 }
        guard let screen = notched ?? NSScreen.main else { return nil }
        return make(for: screen)
    }

    @MainActor
    static func make(for screen: NSScreen) -> NotchGeometry {
        let full = screen.frame
        let height = NotchPillView.contentHeight
        let top = screen.visibleFrame.maxY - 8
        let floating = NSRect(x: full.midX - floatingWidth / 2, y: top - height, width: floatingWidth, height: height)
        let notchHeight = screen.safeAreaInsets.top
        guard notchHeight > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea else {
            return NotchGeometry(metrics: nil, notchOrigin: .zero, floatingFrame: floating)
        }
        let notchWidth = max(0, full.width - left.width - right.width)
        // The expanded panel stops at 70% of the screen.
        let metrics = NotchMetrics(notchWidth: notchWidth, notchHeight: notchHeight, maxExpandedHeight: full.height * 0.7)
        return NotchGeometry(metrics: metrics, notchOrigin: NSPoint(x: full.minX + left.width, y: full.maxY),
                             floatingFrame: floating)
    }

    /// A rect in notch coordinates (y down from the top of the screen) in screen coordinates.
    func screenRect(_ rect: CGRect) -> NSRect {
        NSRect(x: notchOrigin.x + rect.minX, y: notchOrigin.y - rect.maxY, width: rect.width, height: rect.height)
    }

    /// The expanded panel's sections scroll past this height.
    var panelMaxHeight: CGFloat? {
        metrics.map { $0.maxExpandedHeight - $0.notchHeight - Self.footerAllowance }
    }
}

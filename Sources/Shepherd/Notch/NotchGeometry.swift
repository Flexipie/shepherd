import AppKit
import ShepherdUI

/// Where the pill goes. On a notched display it grows out of the notch: flush with the top of
/// the screen, centred on the notch, with its content below the camera. Elsewhere it is a small
/// floating capsule under the menu bar.
struct NotchGeometry: Equatable {
    let frame: NSRect

    static let contentHeight = NotchPillView.contentHeight
    static let minimumWidth: CGFloat = 340

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
        let notchHeight = screen.safeAreaInsets.top
        if notchHeight > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            let notchWidth = max(0, full.width - left.width - right.width)
            let width = max(minimumWidth, notchWidth + 120)
            let height = notchHeight + contentHeight
            let midX = full.minX + left.width + notchWidth / 2
            return NotchGeometry(frame: NSRect(x: midX - width / 2, y: full.maxY - height, width: width, height: height))
        }
        let width = minimumWidth
        let top = screen.visibleFrame.maxY - 8
        return NotchGeometry(frame: NSRect(x: full.midX - width / 2, y: top - contentHeight, width: width, height: contentHeight))
    }
}

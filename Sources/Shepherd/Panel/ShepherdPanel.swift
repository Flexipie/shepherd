import AppKit
import SwiftUI

/// The panel under the menu bar icon. It takes key focus for the arrow keys without activating
/// Shepherd, so the app the user was in stays frontmost and a jump lands straight in the terminal.
final class ShepherdPanel: NSPanel {
    /// Escape.
    var onCancel: (() -> Void)?

    init() {
        super.init(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: true)
        // Set before `level`: making a panel floating resets its level.
        isFloatingPanel = true
        level = .popUpMenu
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient, .ignoresCycle]
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        // The glass draws its own edge; a window shadow would outline the square frame.
        hasShadow = false
        isMovable = false
        isReleasedWhenClosed = false
        animationBehavior = .utilityWindow
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

/// Reports when SwiftUI's preferred size changes, so the panel can resize and keep its top edge
/// under the menu bar.
final class PanelHostingView<Content: View>: NSHostingView<Content> {
    var onSizeChange: (() -> Void)?

    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        onSizeChange?()
    }
}


import AppKit

/// A borderless panel that floats over the menu bar on every Space, including full-screen apps,
/// and never takes focus from the app the user is in.
class NotchPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        // Set before `level`: making a panel floating resets its level.
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
        isReleasedWhenClosed = false
    }

    /// AppKit moves windows out from under the menu bar; the pill belongs there.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// The notch surface's window. Hovering never makes it key, so typing stays in the terminal; a
/// click inside does, without activating Shepherd, and then the arrow keys and Return work.
final class NotchSurfacePanel: NotchPanel {
    /// Escape.
    var onCancel: (() -> Void)?

    override init() {
        super.init()
        becomesKeyOnlyIfNeeded = false
    }

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

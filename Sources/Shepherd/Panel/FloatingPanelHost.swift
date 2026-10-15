import AppKit

/// What the menu bar panel and the palette share: the glass around their content, and the
/// triggers that close them (a click outside, a Space change). Each controller closes on resign
/// key and Escape itself.
@MainActor
final class FloatingPanelHost {
    private var monitors: [Any] = []
    private var spaceObserver: NSObjectProtocol?

    /// `content` inside the glass, for a panel's content view.
    static func glass(_ content: NSView, cornerRadius: CGFloat) -> NSView {
        let glass = NSGlassEffectView()
        glass.cornerRadius = cornerRadius
        glass.contentView = content
        return glass
    }

    /// The screen under the mouse, where a panel opened from a hotkey belongs.
    static var mouseScreen: NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    }

    func startMonitoring(close: @escaping @MainActor () -> Void) {
        stopMonitoring()
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown], handler: { _ in
            MainActor.assumeIsolated { close() }
        }) {
            monitors.append(monitor)
        }
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { close() }
        }
    }

    func stopMonitoring() {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors.removeAll()
        if let spaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver) }
        spaceObserver = nil
    }
}

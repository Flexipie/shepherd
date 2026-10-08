import AppKit
import HerdrKit
import ShepherdModules

/// Skeleton: a menu bar item only. The herdr connection, panel and notch arrive in
/// milestone 1 (docs/ROADMAP.md).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "Shepherd")
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "herdr socket: \(HerdrSocket.defaultPath())", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Shepherd", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

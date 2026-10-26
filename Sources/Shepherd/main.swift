import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: AppController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // `--demo` runs on a made-up herd instead of the user's sources.
        let controller = AppController(demo: CommandLine.arguments.contains("--demo"))
        controller.start()
        self.controller = controller
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.stop()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

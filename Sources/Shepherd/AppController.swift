import AppKit
import HerdrKit
import ShepherdCore
import ShepherdModules

/// Wires the store, modules and surfaces together. Owns everything for the app's lifetime.
@MainActor
final class AppController {
    let store = SessionStore()
    let presence = Presence()
    private let activator: TerminalActivator
    private let modules: [any ShepherdModule]
    private var statusItem: StatusItemController?
    private var notch: NotchController?

    init() {
        activator = TerminalActivator(store: store, presence: presence)
        let context = ModuleContext(store: store, presence: presence, actions: activator)
        modules = BuiltinModules.all.map { $0.init(context: context) }
    }

    func start() {
        statusItem = StatusItemController(store: store, modules: modules, actions: activator)
        notch = NotchController(modules: modules, actions: activator)
        store.start()
    }
}

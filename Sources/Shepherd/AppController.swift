import AppKit
import HerdrSource
import ShepherdCore
import ShepherdModules

/// Wires the store, sources, modules and surfaces together. Owns everything for the app's lifetime.
@MainActor
final class AppController {
    /// `SHEPHERD_TRANSITION_LOG` points the log elsewhere, so runs against a fake herdr do not
    /// mix into real history.
    private let log = TransitionLog(url: ProcessInfo.processInfo.environment["SHEPHERD_TRANSITION_LOG"]
        .map { URL(fileURLWithPath: $0) } ?? TransitionLog.defaultURL)
    private let store: HerdStore
    private let presence = Presence()
    private let actions: AppActions
    private let config = ConfigStore()
    private let registry: ModuleRegistry
    private var statusItem: StatusItemController?
    private var notch: NotchController?

    init() {
        store = HerdStore(log: log)
        actions = AppActions(store: store, presence: presence)
        let context = ModuleContext(store: store, presence: presence, actions: actions, config: config)
        registry = ModuleRegistry(available: BuiltinModules.all, context: context)
    }

    func start() {
        statusItem = StatusItemController(store: store, registry: registry, actions: actions)
        notch = NotchController(registry: registry, actions: actions)
        Task {
            // The log restores exact times in state, so read it before the first snapshot.
            let history = await log.load()
            store.add(HerdrSource(history: history))
            store.start()
            actions.updatePresence()
        }
    }
}

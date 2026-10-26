import AppKit
import ClaudeSessionSource
import HerdrSource
import OpenUsageSource
import ReportSource
import ShellPlugins
import ShepherdCore
import ShepherdModules
import SystemSource
import TmuxSource

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
    private let context: ModuleContext
    private let registry: ModuleRegistry
    private let notifier: SystemNotifier?
    private var statusItem: StatusItemController?
    private var panel: PanelController?
    private var hotKeys: HotKeyCenter?
    private var notch: NotchSurfaceController?
    private var palette: PaletteController?
    private var tmux: TmuxSource?
    /// The source order the running sources were built from. A different one applies at the next launch.
    private var startedOrder: [String] = []

    init() {
        store = HerdStore(log: log)
        actions = AppActions(store: store, presence: presence, config: config)
        notifier = SystemNotifier(store: store, actions: actions, config: config)
        let plugins = PluginHost(runner: ProcessPluginRunner(), store: store, config: config)
        context = ModuleContext(store: store, presence: presence, actions: actions, config: config, notifier: notifier,
                                    usage: OpenUsageReader(), system: MachSystemSampler(),
                                    contextReader: ClaudeContextReader(), plugins: plugins)
        registry = ModuleRegistry(available: BuiltinModules.all, context: context)
    }

    func start() {
        let content = PanelContentSource(store: store, registry: registry, config: config)
        let panel = PanelController(content: content, actions: actions, presence: presence)
        self.panel = panel
        statusItem = StatusItemController(store: store, registry: registry, panel: panel)
        notch = NotchSurfaceController(registry: registry, content: content, actions: actions, presence: presence)
        palette = PaletteController(context: context, registry: registry, actions: actions)
        hotKeys = HotKeyCenter(config: config, bindings: [
            .init(name: "next", combo: \.nextHotkey) { [weak self] in
                self?.closeSurfaces()
                self?.actions.jumpToNext()
            },
            .init(name: "palette", combo: \.paletteHotkey) { [weak self] in
                guard let self else { return }
                if palette?.isOpen != true { closeSurfaces() }
                palette?.toggle()
            },
        ])
        Task {
            // The log restores exact times in state, so read it before the first snapshot.
            let history = await log.load()
            addSources(history: history)
            explainSources()
            context.plugins?.startEvents()
            store.start()
            actions.updatePresence()
        }
    }

    /// The sources in config, in its order (by default herdr, reports, then tmux).
    private func addSources(history: [HerdTransition]) {
        let sources = config.config.sources
        startedOrder = sources.order
        for id in sources.order {
            switch id {
            case "herdr": store.add(HerdrSource(history: history))
            case "report": store.add(ReportSource())
            case "tmux":
                // tmux is optional: without it on the machine there is no source at all.
                guard let tmux = TmuxSource(screens: sources.screens) else { continue }
                self.tmux = tmux
                store.add(tmux)
            default: break
            }
        }
        followSourcesConfig()
    }

    /// Fills the first-run guide. Reading Claude Code's settings is file I/O, so it runs off the main actor.
    private func explainSources() {
        let tmuxInstalled = tmux != nil
        Task {
            let environment = ProcessInfo.processInfo.environment
            let claude = await Task.detached(priority: .utility) { ClaudeSetup.detect(environment: environment) }.value
            context.sourceGuide.set(SourceIntros.make(tmuxInstalled: tmuxInstalled, claude: claude))
        }
    }

    /// Screen patterns apply as soon as the config changes; a different list of sources says it needs a restart.
    private func followSourcesConfig() {
        let sources = withObservationTracking {
            config.config.sources
        } onChange: { [weak self] in
            Task { @MainActor in self?.followSourcesConfig() }
        }
        tmux?.setScreens(sources.screens)
        let restart = sources.order == startedOrder ? nil : "config: sources changed; restart Shepherd to apply"
        config.report(restart, for: "sources")
    }

    /// Closes the menu bar panel, the notch bar and the palette, before a hotkey does its thing.
    private func closeSurfaces() {
        panel?.close()
        notch?.collapse()
        palette?.close()
    }
}

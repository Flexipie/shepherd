import AppKit
import ClaudeSessionSource
import DemoHerd
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
    /// mix into real history. Demo mode keeps none.
    private let log: TransitionLog?
    private let store: HerdStore
    private let presence = Presence()
    private let actions: AppActions
    /// Demo mode reads no config file: it runs with the defaults and writes nothing.
    private let config: ConfigStore
    /// Demo mode: the made-up herd stands in for every source, and nothing of the user's is read.
    private let isDemo: Bool
    private var demo: DemoHerd?
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
    /// The first-run guide has been filled once; after that it is refreshed only when a panel opens.
    private var guideFilled = false

    /// In demo mode no plugin runs and no usage or Claude Code session is read: they are the user's own.
    init(demo: Bool) {
        isDemo = demo
        log = demo ? nil : TransitionLog(url: ProcessInfo.processInfo.environment["SHEPHERD_TRANSITION_LOG"]
            .map { URL(fileURLWithPath: $0) } ?? TransitionLog.defaultURL)
        config = demo ? ConfigStore(fixed: .defaults) : ConfigStore()
        store = HerdStore(log: log)
        actions = AppActions(store: store, presence: presence, config: config)
        notifier = SystemNotifier(store: store, actions: actions, config: config)
        let plugins = demo ? nil : PluginHost(runner: ProcessPluginRunner(), store: store, config: config)
        context = ModuleContext(store: store, presence: presence, actions: actions, config: config, notifier: notifier,
                                    usage: demo ? nil : OpenUsageReader(), system: MachSystemSampler(),
                                    contextReader: demo ? nil : ClaudeContextReader(), plugins: plugins, isDemo: demo)
        registry = ModuleRegistry(available: BuiltinModules.all, context: context)
    }

    func start() {
        let content = PanelContentSource(store: store, registry: registry, config: config)
        let panel = PanelController(content: content, actions: actions, presence: presence)
        self.panel = panel
        statusItem = StatusItemController(store: store, registry: registry, panel: panel, isDemo: isDemo,
                                          canSwitchDemo: Bundle.main.bundleURL.pathExtension == "app") { [weak self] in
            self?.relaunch()
        }
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
            if isDemo {
                await addDemo()
            } else {
                // The log restores exact times in state, so read it before the first snapshot.
                let history = await log?.load() ?? []
                addSources(history: history)
                explainSources()
            }
            context.plugins?.startEvents()
            store.start()
            actions.updatePresence()
        }
    }

    private func addDemo() async {
        // Nothing here touches the user's files, so a failure leaves an empty herd that says why.
        do {
            let demo = try await DemoHerd.start()
            self.demo = demo
            demo.sources.forEach(store.add)
        } catch {
            config.report("demo: could not start the made-up herd (\(error))", for: "demo")
        }
    }

    /// Removes demo mode's temporary socket and reports.
    func stop() {
        demo?.removeFiles()
    }

    /// Opens a new Shepherd in or out of demo mode, then quits this one. The hotkeys are let go
    /// first, so the new one can take them; they come back if it does not open.
    private func relaunch() {
        closeSurfaces()
        hotKeys?.suspend()
        let options = NSWorkspace.OpenConfiguration()
        options.createsNewApplicationInstance = true
        options.arguments = isDemo ? [] : ["--demo"]
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: options) { [weak self] _, error in
            Task { @MainActor in
                if error == nil { NSApp.terminate(nil) } else { self?.hotKeys?.resume() }
            }
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

    /// Fills the first-run guide, then again each time a panel opens while it shows, so installing
    /// Claude Code's hooks is seen without a restart. Reading Claude Code's settings is file I/O, so
    /// it runs off the main actor.
    private func explainSources() {
        let visible = withObservationTracking {
            presence.isPanelVisible
        } onChange: { [weak self] in
            Task { @MainActor in self?.explainSources() }
        }
        guard !guideFilled || (visible && store.agents.isEmpty) else { return }
        guideFilled = true
        let sources = startedOrder, tmuxInstalled = tmux != nil
        Task {
            let environment = ProcessInfo.processInfo.environment
            let claude = await Task.detached(priority: .utility) { ClaudeSetup.detect(environment: environment) }.value
            context.sourceGuide.set(SourceIntros.make(sources: sources, tmuxInstalled: tmuxInstalled, claude: claude,
                                                      canTryDemo: Bundle.main.bundleURL.pathExtension == "app"))
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

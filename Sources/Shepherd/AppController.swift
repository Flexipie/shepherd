import AppKit
import ClaudeSessionSource
import DemoHerd
import HerdrSource
import ReportSource
import ShellPlugins
import ShepherdCore
import ShepherdModules
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
    private var hotKeys: HotKeyCenter?
    private var notch: NotchSurfaceController?
    private var palette: PaletteController?
    private var tmux: TmuxSource?
    /// The source order the running sources were built from. A different one applies at the next launch.
    private var startedOrder: [String] = []
    /// The first-run guide has been filled once; after that it is refreshed only when a surface opens.
    private var guideFilled = false

    /// In demo mode no plugin runs, no notification is posted and no Claude Code session is read:
    /// they are the user's own.
    init(demo: Bool) {
        isDemo = demo
        log = demo ? nil : TransitionLog(url: ProcessInfo.processInfo.environment["SHEPHERD_TRANSITION_LOG"]
            .map { URL(fileURLWithPath: $0) } ?? TransitionLog.defaultURL)
        config = demo ? ConfigStore(fixed: .defaults) : ConfigStore()
        store = HerdStore(log: log)
        actions = AppActions(store: store, presence: presence, config: config)
        // Notifications are shared with any other Shepherd, so a demo posts and withdraws none.
        notifier = demo ? nil : SystemNotifier(store: store, actions: actions, config: config)
        let plugins = demo ? nil : PluginHost(runner: ProcessPluginRunner(), store: store, config: config)
        context = ModuleContext(store: store, presence: presence, actions: actions, config: config, notifier: notifier,
                                    contextReader: demo ? nil : ClaudeContextReader(), plugins: plugins, isDemo: demo,
                                demoTitle: { Self.demoTitle(isDemo: demo) })
        registry = ModuleRegistry(available: BuiltinModules.all, retired: BuiltinModules.retired, context: context)
    }

    func start() {
        let content = PanelContentSource(store: store, registry: registry, config: config)
        let palette = PaletteController(context: context, registry: registry, actions: actions,
                                        switchDemo: { [weak self] in self?.relaunch() },
                                        readSources: { [weak self] in self?.fillGuide() })
        self.palette = palette
        statusItem = StatusItemController(store: store, registry: registry, palette: palette, isDemo: isDemo,
                                          demoItem: context.demoTitle, switchDemo: { [weak self] in self?.relaunch() })
        notch = NotchSurfaceController(registry: registry, content: content, actions: actions, presence: presence)
        hotKeys = HotKeyCenter(config: config, bindings: [
            .init(name: "next", combo: \.nextHotkey) { [weak self] in
                self?.closeSurfaces()
                self?.actions.jumpToNext()
            },
            .init(name: "palette", combo: \.paletteHotkey) { [weak self] in
                guard let self else { return }
                if self.palette?.isOpen != true { closeSurfaces() }
                self.palette?.toggle()
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
            // Manifests before events, so events run and the Gadgets tab shows before the palette first opens.
            await context.plugins?.load()
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

    /// The demo item of the menu and the palette, when this Shepherd runs as an app: Leave Demo in
    /// demo mode, else Try Demo, left out while another Shepherd runs (a second demo would share its
    /// socket and spool).
    private static func demoTitle(isDemo: Bool) -> String? {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return nil }
        if isDemo { return "Leave Demo" }
        return otherShepherdRunning ? nil : "Try Demo"
    }

    private static var otherShepherdRunning: Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .contains { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
    }

    /// Opens a new Shepherd in or out of demo mode, then quits this one. The hotkeys are let go
    /// first, so the new one can take them; they come back if it does not open. Leaving a demo
    /// that runs beside another Shepherd (`make demo`) only quits it.
    private func relaunch() {
        if isDemo, Self.otherShepherdRunning {
            NSApp.terminate(nil)
            return
        }
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

    /// Fills the first-run guide, then again each time the palette or the notch bar opens while it shows, so installing
    /// Claude Code's hooks is seen without a restart.
    private func explainSources() {
        let visible = withObservationTracking {
            presence.isPanelVisible
        } onChange: { [weak self] in
            Task { @MainActor in self?.explainSources() }
        }
        guard !guideFilled || (visible && store.agents.isEmpty) else { return }
        guideFilled = true
        fillGuide()
    }

    /// Reads what each source needs, for the guide and the palette's Status page. Reading Claude
    /// Code's settings is file I/O, so it runs off the main actor. Demo mode has no guide.
    private func fillGuide() {
        guard !isDemo else { return }
        let sources = startedOrder, tmuxInstalled = tmux != nil
        Task {
            let environment = ProcessInfo.processInfo.environment
            let claude = await Task.detached(priority: .utility) { ClaudeSetup.detect(environment: environment) }.value
            let reportBinary = (Bundle.main.executableURL?.deletingLastPathComponent().appending(path: "shepherd-report")
                .path) ?? "shepherd-report"
            context.sourceGuide.set(SourceIntros.make(sources: sources, tmuxInstalled: tmuxInstalled, claude: claude,
                                                      reportBinary: reportBinary,
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

    /// Closes the notch bar and the palette, before a hotkey does its thing.
    private func closeSurfaces() {
        notch?.collapse()
        palette?.close()
    }
}

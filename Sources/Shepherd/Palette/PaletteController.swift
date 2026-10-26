import AppKit
import Observation
import ShepherdCore
import ShepherdModules
import ShepherdUI
import SwiftUI

/// Opens and closes the palette: centred in the upper third of the screen under the mouse, over
/// any app, without activating Shepherd. A fresh view each opening, so the query starts empty.
/// Its prompt and new task pages are its own `StageModel`, which reads an agent's lines only
/// while that agent's prompt shows. It closes on Escape from the list, a click outside, a Space
/// change, losing key, or after an action or a successful send. While open it counts as a panel
/// showing Agents, so agents' context sizes and last messages are read, but never Gadgets. Each
/// opening refreshes the
/// plugins (their manifests and listed actions); ⌘K shows a selection's plugin actions, and an
/// action's printed text stays on a result page.
@MainActor
final class PaletteController: NSObject, NSWindowDelegate {
    private let context: ModuleContext
    private let registry: ModuleRegistry
    private let actions: AppActions
    private let stage: StageModel
    private let plugin = PalettePluginState()
    private let host = FloatingPanelHost()
    private var panel: ShepherdPanel?
    private var hosting: PanelHostingView<PaletteView>?
    private var screen: NSScreen?
    /// Where the top edge sits, fixed for the opening so the palette grows downwards.
    private var top: CGFloat = 0
    /// Bumps on every open, so a stale observation callback from an earlier opening is ignored.
    private var generation = 0

    var isOpen: Bool { panel != nil }

    init(context: ModuleContext, registry: ModuleRegistry, actions: AppActions) {
        self.context = context
        self.registry = registry
        self.actions = actions
        stage = StageModel(store: context.store, actions: actions, config: context.config)
    }

    func toggle() {
        if isOpen { close() } else { open() }
    }

    func open() {
        guard panel == nil, let screen = FloatingPanelHost.mouseScreen else { return }
        self.screen = screen
        top = screen.visibleFrame.maxY - screen.visibleFrame.height * 0.22
        generation += 1
        let panel = ShepherdPanel()
        panel.delegate = self
        panel.onCancel = { [weak self] in self?.cancel() }
        let hosting = PanelHostingView(rootView: view(content()))
        hosting.sizingOptions = [.intrinsicContentSize]
        hosting.onSizeChange = { [weak self] in
            // Resize after SwiftUI finishes the pass that changed the size.
            Task { @MainActor in self?.layout() }
        }
        panel.contentView = FloatingPanelHost.glass(hosting, cornerRadius: 18)
        self.panel = panel
        self.hosting = hosting
        layout()
        panel.makeKeyAndOrderFront(nil)
        host.startMonitoring { [weak self] in self?.close() }
        render(generation)
        // Its agent rows count as the Agents tab, so their context sizes and messages are read.
        context.presence.setPanel("palette", showing: .agents)
        if let plugins = context.plugins { Task { await plugins.refresh() } }
    }

    func close() {
        guard let panel else { return }
        context.presence.setPanel("palette", showing: nil)
        stage.close()
        plugin.page = nil
        host.stopMonitoring()
        panel.delegate = nil
        panel.orderOut(nil)
        panel.contentView = nil
        self.panel = nil
        hosting = nil
    }

    // MARK: Content

    private func content() -> PaletteContent {
        let store = context.store
        let items = PaletteIndex.items(context: context, modules: registry.modules)
        let page: PalettePage = switch (plugin.page, stage.stage(row: { agent in Self.row(for: agent, in: items) })) {
        case (.actions(let target)?, _): .actions(actionsPage(for: target))
        case (.result(let result)?, _): .result(result)
        case (nil, .agent(let agent)?): .prompt(agent)
        case (nil, .newTask(let form)?): .newTask(form)
        case (nil, nil): .list
        }
        return PaletteContent(items: items, notice: store.overallState.isLive ? nil : HerdSummary.lines(store).first, page: page)
    }

    /// The plugin actions for an agent or a project, titled with its name.
    private func actionsPage(for target: PluginTarget) -> PluginActionsPage {
        let store = context.store
        let (title, scope): (String, PluginAction.Context) = switch target {
        case .agent(let id): (store.agents.first { $0.id == id }?.name ?? "agent", .agent)
        case .project(let id): (store.projects.first { $0.id == id }?.name ?? "project", .project)
        case .global: ("Shepherd", .global)
        }
        let actions = context.plugins?.actions(for: scope) ?? []
        return PluginActionsPage(title: title, items: actions.map { plugin, action in
            PaletteIndex.commandItem(PluginsModule.command(plugin, action, target: target))
        })
    }

    private static func row(for agent: AgentID, in items: [PaletteItem]) -> PanelAgentRow? {
        items.lazy.compactMap { item -> PanelAgentRow? in
            if case .agent(let row) = item.kind, row.agent.id == agent { row } else { nil }
        }.first
    }

    private func view(_ content: PaletteContent) -> PaletteView {
        PaletteView(content: content, maxListHeight: maxListHeight) { [weak self] event in
            self?.handle(event)
        }
    }

    /// Re-renders when anything the content reads changes, for as long as this opening lasts.
    private func render(_ opening: Int) {
        guard opening == generation, let hosting else { return }
        let content = withObservationTracking {
            self.content()
        } onChange: { [weak self] in
            Task { @MainActor in self?.render(opening) }
        }
        hosting.rootView = view(content)
    }

    private func handle(_ event: PaletteEvent) {
        switch event {
        case .perform(let action): perform(action)
        case .prompt(let agent): stage.open(agent)
        case .actions(let target): plugin.page = .actions(target)
        case .back:
            if plugin.page != nil { plugin.page = nil } else { stage.close() }
        case .stage(.startTask(let task)): stage.start(task)
        case .stage(let action): stage.send(action) { [weak self] in self?.close() }
        }
    }

    private func perform(_ action: PaletteAction) {
        if case .newTask(let project) = action { return stage.openNewTask(in: project) }
        if case .plugin(let ref) = action { return run(ref) }
        close()
        switch action {
        case .jump(let agent): actions.jump(to: agent)
        case .focusProject(let project): actions.focusProject(project)
        case .nextInQueue: actions.jumpToNext()
        case .newTask, .plugin: break
        }
    }

    /// Runs a plugin action with the palette showing it. No text closes the palette; text or a
    /// failure stays on the result page.
    private func run(_ ref: PluginActionRef) {
        guard let plugins = context.plugins, let (_, action) = plugins.action(ref) else { return }
        let opening = generation
        plugin.page = .result(PluginResultPage(title: action.title, isRunning: true))
        Task { @MainActor in
            let page: PluginResultPage?
            do {
                page = try await plugins.run(ref).map { PluginResultPage(title: action.title, text: $0) }
            } catch {
                page = PluginResultPage(title: action.title, error: (error as? ConfigProblem)?.message ?? "\(error)")
            }
            guard opening == generation, isOpen, case .result(let shown)? = plugin.page, shown.isRunning else { return }
            if let page { plugin.page = .result(page) } else { close() }
        }
    }

    /// Escape: back to the list from another page, else close.
    private func cancel() {
        let mode: PaletteMode = switch (plugin.page, stage.mode) {
        case (.actions?, _): .actions
        case (.result?, _): .result
        case (nil, .agent?): .prompt
        case (nil, .newTask?): .newTask
        case (nil, nil): .list
        }
        switch mode.handle(.escape, canPromptSelection: false, fieldEmpty: true) {
        case .back: stage.close()
        case .close: close()
        case .prompt, .swallow, .pass: break
        }
    }

    // MARK: Layout

    /// About nine agent rows, and never past the bottom of the screen.
    private var maxListHeight: CGFloat {
        min(9 * 44, ((screen ?? NSScreen.main)?.visibleFrame.height ?? 800) * 0.6)
    }

    private func layout() {
        guard let panel, let hosting, let screen else { return }
        let visible = screen.visibleFrame
        let width = PaletteView.width
        let height = min(hosting.fittingSize.height, top - visible.minY - 8)
        let x = visible.midX - width / 2
        panel.setFrame(NSRect(x: x, y: top - height, width: width, height: height), display: true)
    }

    func windowDidResignKey(_ notification: Notification) {
        close()
    }
}

/// The palette's plugin pages, observed so the palette redraws when they change.
@MainActor
@Observable
final class PalettePluginState {
    enum Page: Equatable {
        case actions(PluginTarget)
        case result(PluginResultPage)
    }

    var page: Page?
}

import Observation
import ShepherdCore

/// The user's plugins in the palette and on the Gadgets tab: each global action is a command,
/// and each gadget a card. Project and agent actions show on ⌘K for the selected project or
/// agent, and Open plugins folder is a command too. Gadgets run only while a surface shows the
/// Gadgets tab: once on showing it, then every `every` seconds. With no gadget plugin there is no section and no Gadgets command, so no tab.
/// Opening a panel reads the manifests again, so a plugin dropped in shows. With no plugin host
/// in the context it offers nothing.
@MainActor
public final class PluginsModule: ShepherdModule {
    public static let id = "plugins"
    private let context: ModuleContext
    /// The running gadget loops, with the plugin each was started for.
    private(set) var loops: [String: (plugin: Plugin, task: Task<Void, Never>)] = [:]
    private var wasPanelVisible = false

    public init(context: ModuleContext) {
        self.context = context
        watch()
    }

    /// Turned off while Gadgets shows, its loops would otherwise run on, and a failure would stay
    /// in the footer.
    isolated deinit {
        loops.values.forEach { $0.task.cancel() }
        context.plugins?.forgetGadgets()
    }

    public var panel: PanelSection? {
        guard let plugins = context.plugins, !plugins.gadgetPlugins.isEmpty else { return nil }
        return PanelSection(id: Self.id, title: "Gadgets", items: Self.cards(plugins).map(PanelItem.gadget), emptyText: "Running…",
                            tab: .gadgets)
    }

    public var commands: [PaletteCommand] {
        guard let plugins = context.plugins else { return [] }
        let folder = PaletteCommand(id: "plugins.folder", title: "Open plugins folder", symbol: "folder", action: .openPluginsFolder)
        let actions = plugins.actions(for: .global).map { plugin, action in
            Self.command(plugin, action, target: .global)
        }
        guard !plugins.gadgetPlugins.isEmpty else { return actions + [folder] }
        return actions + [PaletteCommand(id: "plugins.gadgets", title: "Gadgets", symbol: "square.grid.2x2",
                                         keywords: ["plugin", "widgets"], action: .gadgets), folder]
    }

    /// Every gadget's card that has run, in plugin order.
    public static func cards(_ plugins: PluginHost) -> [GadgetCard] {
        plugins.gadgetPlugins.compactMap(plugins.gadgetCard(for:))
    }

    /// A plugin action as a palette command on `target`.
    public static func command(_ plugin: Plugin, _ action: PluginAction, target: PluginTarget) -> PaletteCommand {
        PaletteCommand(id: "plugins.\(plugin.id).\(action.id)", title: action.title, symbol: action.symbol ?? "puzzlepiece.extension",
                       keywords: [plugin.manifest.name, "plugin"],
                       action: .plugin(PluginActionRef(plugin: plugin.id, action: action.id, target: target)))
    }

    /// Starts a loop for each gadget while the tab shows and stops it after; a plugin that
    /// changed gets a new loop. Stopping a loop leaves a run in progress to finish.
    private func watch() {
        guard let plugins = context.plugins else { return }
        let presence = context.presence
        let (showing, visible, gadgets) = withObservationTracking {
            (presence.isShowing(.gadgets), presence.isPanelVisible, plugins.gadgetPlugins)
        } onChange: { [weak self] in
            Task { @MainActor in self?.watch() }
        }
        if visible, !wasPanelVisible { Task { await plugins.load() } }
        wasPanelVisible = visible
        let wanted = showing ? gadgets : []
        for (id, loop) in loops where !wanted.contains(loop.plugin) {
            loop.task.cancel()
            loops[id] = nil
        }
        for plugin in wanted where loops[plugin.id] == nil {
            guard let every = plugin.manifest.gadget?.every else { continue }
            loops[plugin.id] = (plugin, Task { @MainActor in
                while !Task.isCancelled {
                    plugins.runGadget(plugin)
                    try? await Task.sleep(for: .seconds(every))
                }
            })
        }
    }
}

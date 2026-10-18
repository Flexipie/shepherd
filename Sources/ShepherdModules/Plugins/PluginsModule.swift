import ShepherdCore

/// The user's plugins in the palette: each global action is a command. Project and agent actions
/// show on ⌘K for the selected project or agent. With no plugin host in the context it offers
/// nothing.
@MainActor
public final class PluginsModule: ShepherdModule {
    public static let id = "plugins"
    private let context: ModuleContext

    public init(context: ModuleContext) {
        self.context = context
    }

    public var commands: [PaletteCommand] {
        guard let plugins = context.plugins else { return [] }
        return plugins.actions(for: .global).map { plugin, action in
            Self.command(plugin, action, target: .global)
        }
    }

    /// A plugin action as a palette command on `target`.
    public static func command(_ plugin: Plugin, _ action: PluginAction, target: PluginTarget) -> PaletteCommand {
        PaletteCommand(id: "plugins.\(plugin.id).\(action.id)", title: action.title, symbol: action.symbol ?? "puzzlepiece.extension",
                       keywords: [plugin.manifest.name, "plugin"],
                       action: .plugin(PluginActionRef(plugin: plugin.id, action: action.id, target: target)))
    }
}

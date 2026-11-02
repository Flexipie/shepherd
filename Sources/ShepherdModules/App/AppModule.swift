import ShepherdCore

/// Shepherd's own commands in the palette: Status, Quit, and Open config file while there is a
/// config path (demo mode has none).
@MainActor
public final class AppModule: ShepherdModule {
    public static let id = "app"
    /// The Status command's id, so the palette points to it only while it is on offer.
    public static let statusCommand = "app.status"
    private let context: ModuleContext

    public init(context: ModuleContext) {
        self.context = context
    }

    public var commands: [PaletteCommand] {
        let quit = PaletteCommand(id: "app.quit", title: "Quit", symbol: "power", action: .quit,
                                  onlyWhenTyped: true)
        let status = PaletteCommand(id: Self.statusCommand, title: "Status", symbol: "stethoscope",
                                    keywords: ["sources", "problems", "connect", "hotkey", "health"], action: .status)
        guard context.config.url != nil else { return [status, quit] }
        return [status, PaletteCommand(id: "app.config", title: "Open config file", symbol: "doc.text", keywords: ["settings", "json"],
                                       action: .openConfig), quit]
    }
}

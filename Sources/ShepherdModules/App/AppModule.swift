import ShepherdCore

/// Shepherd's own commands in the palette: Quit, and Open config file while there is a
/// config path (demo mode has none).
@MainActor
public final class AppModule: ShepherdModule {
    public static let id = "app"
    private let context: ModuleContext

    public init(context: ModuleContext) {
        self.context = context
    }

    public var commands: [PaletteCommand] {
        let quit = PaletteCommand(id: "app.quit", title: "Quit", symbol: "power", keywords: ["exit"], action: .quit)
        guard context.config.url != nil else { return [quit] }
        return [PaletteCommand(id: "app.config", title: "Open config file", symbol: "doc.text", keywords: ["settings", "json"],
                               action: .openConfig), quit]
    }
}

import ShepherdCore

/// Says, at the top of the panel, that the herd is demo mode's made-up one and how to leave it.
/// Outside demo mode it has no section.
@MainActor
public final class DemoModule: ShepherdModule {
    public static let id = "demo"
    private let context: ModuleContext

    public init(context: ModuleContext) {
        self.context = context
    }

    public var panel: PanelSection? {
        guard context.isDemo else { return nil }
        let card = GadgetCard(id: "demo", title: "Demo herd", detail: "made up", lines: [
            "These agents are not real. Nothing here reaches herdr, tmux or your files.",
            "Right-click the menu bar icon and choose Leave Demo.",
        ])
        return PanelSection(id: Self.id, title: "Demo", items: [.gadget(card)], emptyText: "")
    }
}

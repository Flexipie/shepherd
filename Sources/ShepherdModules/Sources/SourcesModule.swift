import ShepherdCore

/// The first-run guide: while the herd has no agents, a card per place agents can come from, saying
/// whether Shepherd found it, what it gives, and what to do to get it. It goes away once an agent
/// shows, so it costs nothing in daily use. With nothing in the guide it has no section.
@MainActor
public final class SourcesModule: ShepherdModule {
    public static let id = "sources"
    private let context: ModuleContext

    public init(context: ModuleContext) {
        self.context = context
    }

    public var panel: PanelSection? {
        let guide = context.sourceGuide
        guard context.store.agents.isEmpty, !guide.intros.isEmpty else { return nil }
        let cards = guide.intros.map { intro in
            let on = guide.isOn(intro, in: context.store)
            let text = on ? intro.on : intro.off
            return PanelItem.gadget(GadgetCard(id: intro.id, title: intro.name, detail: text.detail, lines: [text.line],
                                               isStale: !on))
        }
        return PanelSection(id: Self.id, title: "Where agents come from", items: cards, emptyText: "")
    }
}

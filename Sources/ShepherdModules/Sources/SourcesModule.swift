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
        guard context.store.agents.isEmpty, !context.sourceGuide.intros.isEmpty else { return nil }
        return PanelSection(id: Self.id, title: "Where agents come from", items: cards(tips: true).map(PanelItem.gadget), emptyText: "")
    }

    /// A card per place agents can come from, whether or not agents show. Without `tips`, cards
    /// that are not a source (Try Demo) are left out, for the palette's Status page.
    public func cards(tips: Bool) -> [GadgetCard] {
        let guide = context.sourceGuide
        return guide.intros.filter { tips || !$0.isTip }.map { intro in
            let on = guide.isOn(intro, in: context.store)
            let text = on ? intro.on : intro.off
            // Not `isStale`: a source that is off is not out of date, and VoiceOver would say so.
            // One line per `\n`, so a command sits on a line of its own and copies without the prose.
            return GadgetCard(id: intro.id, title: intro.name, detail: text.detail,
                              lines: text.line.components(separatedBy: "\n"))
        }
    }
}

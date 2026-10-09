import ShepherdCore

/// The needs-you queue at the top of the panel: blocked first, then finished, longest waiting
/// first, from live sources only. Stale state is not a reason to go somewhere.
@MainActor
public final class QueueModule: ShepherdModule {
    public static let id = "queue"
    private let context: ModuleContext

    public init(context: ModuleContext) {
        self.context = context
    }

    public var panel: PanelSection? {
        let store = context.store
        let rows = store.needsYou
            .filter { store.sourceStates[$0.id.source]?.isLive == true }
            .map { agent in
                PanelAgentRow(agent: agent, tokens: context.tokenLines(.agents, values: agent.tokens, source: agent.id.source),
                              action: canFocus(agent.id.source) ? .jump(agent.id) : nil)
            }
        return PanelSection(id: Self.id, title: "Needs you", items: rows.map(PanelItem.agent), emptyText: "Nothing needs you")
    }

    private func canFocus(_ source: SourceID) -> Bool {
        context.store.source(source)?.capabilities.contains(.focus) == true
    }
}

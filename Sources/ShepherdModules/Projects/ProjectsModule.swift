import ShepherdCore

/// One card per project, in each source's own order: its tokens, then each agent with its state,
/// time in state and tokens. Projects without agents are still shown, since they are somewhere
/// to go. A source that is not live shows its last known state, dimmed, never as current.
@MainActor
public final class ProjectsModule: ShepherdModule {
    public static let id = "projects"
    private let context: ModuleContext

    public init(context: ModuleContext) {
        self.context = context
    }

    public var panel: PanelSection? {
        let store = context.store
        let byProject = Dictionary(grouping: store.agents.filter { $0.projectID != nil }) { $0.projectID! }
        var cards = store.projects.map { project in
            card(project, agents: byProject[project.id] ?? [], action: can(.focusProject, project.id.source) ? .focusProject(project.id) : nil)
        }
        // Agents whose source has no projects get one card per source, so none go missing.
        let loose = store.agents.filter { $0.projectID == nil }
        for source in store.sources where loose.contains(where: { $0.id.source == source.id }) {
            let project = HerdProject(id: ProjectID(source: source.id, local: ""), name: source.displayName)
            cards.append(card(project, agents: loose.filter { $0.id.source == source.id }, action: nil))
        }
        return PanelSection(id: Self.id, title: "Projects", items: cards.map(PanelItem.project), emptyText: "No projects")
    }

    private func card(_ project: HerdProject, agents: [HerdAgent], action: PanelAction?) -> PanelProjectCard {
        let source = project.id.source
        let live = context.store.sourceStates[source]?.isLive == true
        let canJump = can(.focus, source)
        let rows = agents.map { agent in
            PanelAgentRow(agent: agent, tokens: context.tokenLines(.agents, values: agent.tokens, source: source),
                          isLive: live, action: canJump ? .jump(agent.id) : nil)
        }
        return PanelProjectCard(project: project, tokens: context.tokenLines(.projects, values: project.tokens, source: source),
                                agents: rows, isLive: live, action: action)
    }

    private func can(_ capability: SourceCapabilities, _ source: SourceID) -> Bool {
        context.store.source(source)?.capabilities.contains(capability) == true
    }
}

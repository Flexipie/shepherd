import ShepherdCore

/// One card per project, in each source's own order: its tokens, then each agent with its state,
/// time in state and tokens. Projects without agents are still shown, since they are somewhere
/// to go. A source that is not live shows its last known state, dimmed, never as current.
/// Checkouts of one repo share a card, at the place of the first, with the main checkout first.
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
        return PanelSection(id: Self.id, title: "Projects", items: Self.grouped(cards), emptyText: "No projects")
    }

    /// Cards of two or more checkouts of one repo become one repo card where the first of them
    /// was: the main checkout first, then linked worktrees in source order. A lone checkout, or a
    /// project with no repo, stays a plain card.
    static func grouped(_ cards: [PanelProjectCard]) -> [PanelItem] {
        func key(_ card: PanelProjectCard) -> String? {
            card.project.repo.map { "\(card.project.id.source)/\($0.key)" }
        }
        let members = Dictionary(grouping: cards.filter { key($0) != nil }) { key($0)! }
        var placed: Set<String> = []
        return cards.compactMap { card in
            guard let key = key(card), let group = members[key], group.count > 1 else { return .project(card) }
            guard placed.insert(key).inserted else { return nil }
            let ordered = group.filter { $0.project.repo?.isLinkedCheckout == false } + group.filter { $0.project.repo?.isLinkedCheckout == true }
            let name = card.project.repo?.name ?? ""
            return .repo(PanelRepoCard(key: key, name: name.isEmpty ? ordered[0].project.name : name, projects: ordered))
        }
    }

    /// "New task…", then "New task in <project>" for each live project a task can start in.
    public var commands: [PaletteCommand] {
        let store = context.store
        let projects = store.projects.filter { store.sourceStates[$0.id.source]?.isLive == true && store.canStartTask(in: $0.id) }
        guard !projects.isEmpty else { return [] }
        let keywords = ["start", "agent", "worktree", "branch"]
        return [PaletteCommand(id: "projects.new-task", title: "New task…", symbol: "plus", keywords: keywords, action: .newTask(nil))]
            + projects.map { project in
                PaletteCommand(id: "projects.new-task.\(project.id)", title: "New task in \(project.name.isEmpty ? "Untitled" : project.name)",
                               symbol: "plus", keywords: keywords, action: .newTask(project.id))
            }
    }

    private func card(_ project: HerdProject, agents: [HerdAgent], action: PanelAction?) -> PanelProjectCard {
        let source = project.id.source
        let live = context.store.sourceStates[source]?.isLive == true
        let canJump = can(.focus, source)
        let rows = agents.map { agent in
            PanelAgentRow(agent: agent, tokens: context.tokenLines(.agents, values: context.tokens(of: agent), source: source),
                          isLive: live, action: canJump ? .jump(agent.id) : nil,
                          contextTokens: context.agentContext.tokens[agent.id])
        }
        return PanelProjectCard(project: project, tokens: context.tokenLines(.projects, values: context.tokens(of: project), source: source),
                                agents: rows, isLive: live, action: action)
    }

    private func can(_ capability: SourceCapabilities, _ source: SourceID) -> Bool {
        context.store.source(source)?.capabilities.contains(capability) == true
    }
}

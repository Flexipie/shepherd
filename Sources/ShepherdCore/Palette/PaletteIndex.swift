/// Everything the palette can find, in its order with no query: agents that need the user in
/// queue order, then the other agents, then projects, then each module's commands. Only live
/// sources count: stale state is not a reason to go somewhere. Read inside observation tracking
/// to rebuild when any of it changes.
@MainActor
public enum PaletteIndex {
    public static func items(context: ModuleContext, modules: [any ShepherdModule]) -> [PaletteItem] {
        let store = context.store
        let live = Set(store.sources.map(\.id).filter { store.sourceStates[$0]?.isLive == true })
        let projects = Dictionary(store.projects.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let waiting = store.needsYou.filter { live.contains($0.id.source) }
        let others = store.agents.filter { live.contains($0.id.source) && !$0.status.needsYou }
        let agents = (waiting + others).map { agentItem($0, project: $0.projectID.flatMap { projects[$0] }, context: context) }
        let projectItems = store.projects.filter { live.contains($0.id.source) }.map { projectItem($0, context: context) }
        let commands = modules.flatMap(\.commands).map(commandItem)
        return agents + projectItems + commands
    }

    public static func commandItem(_ command: PaletteCommand) -> PaletteItem {
        PaletteItem(id: "command/\(command.id)", kind: .command(command), searchText: [command.title] + command.keywords,
                    action: command.action)
    }

    private static func agentItem(_ agent: HerdAgent, project: HerdProject?, context: ModuleContext) -> PaletteItem {
        let canFocus = can(.focus, agent.id.source, context)
        let canPrompt = can(agent.status == .blocked ? .sendText : .prompt, agent.id.source, context)
        let agentTokens = context.tokens(of: agent)
        let row = PanelAgentRow(agent: agent, tokens: context.tokenLines(.agents, values: agentTokens, source: agent.id.source),
                                action: canFocus ? .jump(agent.id) : nil, contextTokens: context.agentContext.tokens[agent.id])
        let words = [agent.kind ?? "", agent.project, project?.repo?.name ?? "", agent.statusText] + values(agentTokens)
            + values(project.map(context.tokens(of:)) ?? [:])
        return PaletteItem(id: "agent/\(agent.id)", kind: .agent(row), searchText: [agent.name] + words.filter { !$0.isEmpty },
                           action: canFocus ? .jump(agent.id) : nil, canPrompt: canPrompt)
    }

    private static func projectItem(_ project: HerdProject, context: ModuleContext) -> PaletteItem {
        let source = project.id.source
        let projectTokens = context.tokens(of: project)
        let tokens = context.tokenLines(.projects, values: projectTokens, source: source)
        return PaletteItem(id: "project/\(project.id)",
                           kind: .project(project, agentCount: context.store.agents(in: project.id).count, tokens: tokens),
                           searchText: [project.name] + ([project.repo?.name ?? ""] + values(projectTokens)).filter { !$0.isEmpty },
                           action: can(.focusProject, source, context) ? .focusProject(project.id) : nil)
    }

    /// Token values in a stable order.
    private static func values(_ tokens: [String: String]) -> [String] {
        tokens.keys.sorted().compactMap { tokens[$0] }
    }

    private static func can(_ capability: SourceCapabilities, _ source: SourceID, _ context: ModuleContext) -> Bool {
        context.store.source(source)?.capabilities.contains(capability) == true
    }
}

import Observation
import ShepherdCore

/// The context size and last message of agents whose session a reader understands (Claude Code
/// for now), shown on their rows, the palette and the stage. It has no section of its own: it
/// fills `ModuleContext.agentContext`, which row builders read. It reads only while a panel or
/// the palette shows agents: every agent with a session on showing them, then an agent again when
/// its status, the time it entered it or its session changes (a cleared or resumed session).
/// Otherwise nothing is read. Turned off, what it read goes away with it.
@MainActor
public final class ContextModule: ShepherdModule {
    public static let id = "context"

    private let context: ModuleContext
    private var isVisible = false
    /// What each agent's read was asked for: its status, since when, and its session.
    private struct ReadState: Equatable {
        let status: HerdStatus
        let since: Since?
        let session: AgentSession?

        init(_ agent: HerdAgent) {
            status = agent.status
            since = agent.since
            session = agent.session
        }
    }

    /// Each agent's state when it was last read, to see which changed since.
    private var readState: [AgentID: ReadState] = [:]
    private var reading: Set<AgentID> = []
    /// Agents whose status changed while their read was on its way; read once more after it.
    private var again: Set<AgentID> = []

    public init(context: ModuleContext) {
        self.context = context
        watchVisibility()
        watchAgents()
    }

    isolated deinit {
        context.agentContext.removeAll()
    }

    private func watchVisibility() {
        let visible = withObservationTracking {
            context.presence.isShowing(.agents)
        } onChange: { [weak self] in
            Task { @MainActor in self?.watchVisibility() }
        }
        guard visible != isVisible else { return }
        isVisible = visible
        guard visible else { return }
        readState = [:]
        readChanged()
    }

    private func watchAgents() {
        let agents = withObservationTracking {
            context.store.agents
        } onChange: { [weak self] in
            Task { @MainActor in self?.watchAgents() }
        }
        let ids = Set(agents.map(\.id))
        context.agentContext.keep(only: ids)
        readState = readState.filter { ids.contains($0.key) }
        if isVisible { readChanged() }
    }

    /// Reads every agent with a session whose state differs from when it was last read.
    private func readChanged() {
        guard context.contextReader != nil, context.presence.isShowing(.agents) else { return }
        for agent in context.store.agents where readState[agent.id] != ReadState(agent) {
            guard let session = agent.session else { continue }
            readState[agent.id] = ReadState(agent)
            read(agent.id, session)
        }
    }

    private func read(_ agent: AgentID, _ session: AgentSession) {
        guard let reader = context.contextReader else { return }
        guard reading.insert(agent).inserted else {
            again.insert(agent)
            return
        }
        Task { @MainActor [weak self] in
            let found = try? await reader.read(session)
            guard let self else { return }
            reading.remove(agent)
            if context.store.agents.contains(where: { $0.id == agent }) {
                context.agentContext.set(found?.contextTokens, for: agent)
                context.agentContext.set(finalMessage: found?.finalMessage, for: agent)
            }
            if again.remove(agent) != nil, context.presence.isShowing(.agents),
               let current = context.store.agents.first(where: { $0.id == agent }), let session = current.session {
                read(agent, session)
            }
        }
    }
}

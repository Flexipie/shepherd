import Foundation
import Observation

/// The whole herd, merged from every source. Each property changes only when its value does, so
/// a surface that reads only `needsYou` is not redrawn by unrelated updates.
@MainActor
@Observable
public final class HerdStore {
    /// Every agent, grouped by source in the order sources were added.
    public private(set) var agents: [HerdAgent] = []
    /// Every project, grouped by source in the order sources were added, each source's in its own order.
    public private(set) var projects: [HerdProject] = []
    /// Agents waiting on the user, across sources: blocked first, then finished, longest waiting first.
    public private(set) var needsYou: [HerdAgent] = []
    public private(set) var workingCount = 0
    public private(set) var sourceStates: [SourceID: SourceState] = [:]
    public private(set) var statusLines: [SourceID: [String]] = [:]
    /// Each source's own token styling.
    public private(set) var tokenLayouts: [SourceID: TokenLayout] = [:]
    /// Sources that post their own system notifications.
    public private(set) var sourcesPostingAlerts: Set<SourceID> = []
    /// The transitions behind the most recent update that had any.
    public private(set) var lastTransitions: [HerdTransition] = []

    @ObservationIgnored public private(set) var sources: [any AgentSource] = []
    @ObservationIgnored private var bySource: [SourceID: SourceUpdate] = [:]
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private let log: TransitionLog?
    @ObservationIgnored private var subscribers: [UUID: AsyncStream<HerdEvent>.Continuation] = [:]
    /// Agents seen by two sources and shown as one row, as of the last update.
    @ObservationIgnored private var merges: [HerdMerge] = []

    public init(log: TransitionLog? = nil) {
        self.log = log
    }

    public func add(_ source: any AgentSource) {
        sources.append(source)
        sourceStates[source.id] = .connecting
    }

    public func start() {
        guard tasks.isEmpty else { return }
        for source in sources {
            let id = source.id
            let updates = source.updates
            source.start()
            tasks.append(Task { [weak self] in
                for await update in updates { self?.apply(update, from: id) }
            })
        }
    }

    public func stop() async {
        for task in tasks { task.cancel() }
        tasks.removeAll()
        for source in sources { await source.stop() }
    }

    public func source(_ id: SourceID) -> (any AgentSource)? {
        sources.first { $0.id == id }
    }

    /// Focuses the agent in its source and brings the source's app forward.
    public func focus(_ agent: AgentID) async throws {
        guard let source = source(agent.source) else { throw AgentSourceError.unknownSource(agent.source) }
        guard source.capabilities.contains(.focus) else { throw AgentSourceError.unsupported(.focus) }
        try await source.focus(agent)
    }

    /// Shows the project in its source and brings the source's app forward.
    public func focusProject(_ project: ProjectID) async throws {
        guard let source = source(project.source) else { throw AgentSourceError.unknownSource(project.source) }
        guard source.capabilities.contains(.focusProject) else { throw AgentSourceError.unsupported(.focusProject) }
        try await source.focusProject(project)
    }

    /// What the agent's source can do; empty for an unknown source.
    public func capabilities(of agent: AgentID) -> SourceCapabilities {
        source(agent.source)?.capabilities ?? []
    }

    /// The agent's last visible lines.
    public func read(_ agent: AgentID, lines: Int) async throws -> String {
        try await source(for: agent, needing: .readOutput).read(agent, lines: lines)
    }

    /// Presses keys in the agent.
    public func sendKeys(_ agent: AgentID, _ keys: [String]) async throws {
        try await source(for: agent, needing: .sendKeys).sendKeys(agent, keys)
    }

    /// Types text into the agent and presses Return.
    public func sendText(_ agent: AgentID, _ text: String) async throws {
        try await source(for: agent, needing: .sendText).sendText(agent, text)
    }

    /// Submits a prompt to an agent that is not waiting on a question.
    public func prompt(_ agent: AgentID, _ text: String) async throws {
        try await source(for: agent, needing: .prompt).prompt(agent, text)
    }

    /// Whether the project's source can start tasks in it.
    public func canStartTask(in project: ProjectID) -> Bool {
        source(project.source)?.capabilities.isSuperset(of: [.createWorktree, .startAgent]) == true
    }

    /// Starts a task: a checkout, an agent in it, its prompt. Returns the new agent.
    public func startTask(_ task: NewTask, args: [String]) async throws -> AgentID {
        guard let source = source(task.project.source) else { throw AgentSourceError.unknownSource(task.project.source) }
        guard canStartTask(in: task.project) else { throw AgentSourceError.unsupported(.startAgent) }
        let agent = try await source.startTask(task, args: args)
        publish(.taskStarted(agent, task.project))
        return agent
    }

    /// Every event from now on, in order. Nothing is dropped while a consumer is busy; the stream
    /// ends, and stops costing anything, once the consumer stops iterating.
    public func events() -> AsyncStream<HerdEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: HerdEvent.self, bufferingPolicy: .unbounded)
        let id = UUID()
        subscribers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.subscribers[id] = nil }
        }
        return stream
    }

    private func publish(_ event: HerdEvent) {
        for continuation in subscribers.values { continuation.yield(event) }
    }

    private func source(for agent: AgentID, needing capability: SourceCapabilities) throws -> any AgentSource {
        guard let source = source(agent.source) else { throw AgentSourceError.unknownSource(agent.source) }
        guard source.capabilities.contains(capability) else { throw AgentSourceError.unsupported(capability) }
        return source
    }

    /// The project's agents, in source order.
    public func agents(in project: ProjectID) -> [HerdAgent] {
        agents.filter { $0.projectID == project }
    }

    /// Live only when every source is; otherwise the first source's problem, so the user hears
    /// about it. An absent source is not a problem: someone without herdr is not "not connected".
    /// Never `.absent` itself.
    public var overallState: SourceState {
        // Read the observed dictionary first: `sources` is not observed, and with no sources yet
        // nothing else here would register a dependency, so a surface would never update.
        let observed = sourceStates
        let states = sources.compactMap { observed[$0.id] }
        if states.isEmpty { return .connecting }
        return states.first { !$0.isLive && !$0.isAbsent } ?? .live
    }

    package func apply(_ update: SourceUpdate, from source: SourceID) {
        bySource[source] = update
        let previousMerges = merges
        let (merged, mergedProjects) = mergedHerd()
        if agents != merged { agents = merged }
        if projects != mergedProjects { projects = mergedProjects }
        let waiting = merged.filter(\.status.needsYou).sorted(by: Self.waitingOrder)
        if needsYou != waiting { needsYou = waiting }
        let working = merged.count { $0.status == .working }
        if workingCount != working { workingCount = working }
        if sourceStates[source] != update.state { sourceStates[source] = update.state }
        if statusLines[source] != update.statusLines { statusLines[source] = update.statusLines }
        if tokenLayouts[source] != update.tokenLayout { tokenLayouts[source] = update.tokenLayout }
        if sourcesPostingAlerts.contains(source) != update.postsSystemAlerts {
            if update.postsSystemAlerts { sourcesPostingAlerts.insert(source) } else { sourcesPostingAlerts.remove(source) }
        }
        // A merged row's changes are told once, under its row's id. A pair that just ended still
        // decides, so a report going away is not told as its own agent leaving.
        let transitions = update.transitions.compactMap { transition in
            let merge = (merges + previousMerges).first { $0.host == transition.agent || $0.guest == transition.agent }
            return merge.map { $0.view(of: transition) } ?? transition
        }
        if !transitions.isEmpty {
            lastTransitions = transitions
            if let log { Task { await log.append(transitions) } }
            // A screen reading is a guess, so no event announces it: plugins run for reported changes only.
            let inferred = Set(update.agents.filter(\.isInferred).map(\.id))
            let announced = transitions.filter { !inferred.contains($0.agent) }
            if !announced.isEmpty { publish(.transitions(announced)) }
        }
    }

    /// Every source's agents and projects. An agent two sources see is one row (`HerdMerge`): the
    /// row of the source that can act on it, with a report's state over a screen reading. A project
    /// is dropped when only a folded-in agent used it. A project read from a screen is dropped once
    /// no agent is left in it and a reported project is in its folder (a screen's project is a whole
    /// checkout, a report's the agent's own folder).
    private func mergedHerd() -> (agents: [HerdAgent], projects: [HerdProject]) {
        let all = sources.flatMap { bySource[$0.id]?.agents ?? [] }
        let byID = Dictionary(all.map { ($0.id, $0) }) { first, _ in first }
        merges = HerdMerge.find(in: all) { source($0)?.capabilities ?? [] }
        let byHost = Dictionary(merges.map { ($0.host, $0) }) { first, _ in first }
        let guests = Set(merges.map(\.guest))
        let kept: [HerdAgent] = all.compactMap { agent in
            if guests.contains(agent.id) { return nil }
            guard let merge = byHost[agent.id], let guest = byID[merge.guest] else { return agent }
            return merge.row(host: agent, guest: guest)
        }
        let inUse = Set(kept.compactMap(\.projectID))
        let guestProjects = Set(guests.compactMap { byID[$0]?.projectID })
        let allProjects = sources.flatMap { bySource[$0.id]?.projects ?? [] }
            .filter { !guestProjects.contains($0.id) || inUse.contains($0.id) }
        let reportedPaths = Set(allProjects.filter { !$0.isInferred }.compactMap(\.path))
        let projects = allProjects.filter { project in
            let shadowed = project.path.map { path in
                reportedPaths.contains { $0 == path || $0.hasPrefix(path.hasSuffix("/") ? path : path + "/") }
            } ?? false
            return !(project.isInferred && shadowed && !inUse.contains(project.id))
        }
        return (kept, projects)
    }

    static func waitingOrder(_ a: HerdAgent, _ b: HerdAgent) -> Bool {
        if (a.status == .blocked) != (b.status == .blocked) { return a.status == .blocked }
        switch (a.since?.date, b.since?.date) {
        case let (x?, y?) where x != y: return x < y
        case (_?, nil): return true
        case (nil, _?): return false
        default: return a.id.description < b.id.description
        }
    }
}

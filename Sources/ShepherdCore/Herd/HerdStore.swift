import Foundation
import Observation

/// The whole herd, merged from every source. Each property changes only when its value does, so
/// a surface that reads only `needsYou` is not redrawn by unrelated updates.
@MainActor
@Observable
public final class HerdStore {
    /// Every agent, grouped by source in the order sources were added.
    public private(set) var agents: [HerdAgent] = []
    /// Agents waiting on the user, across sources: blocked first, then finished, longest waiting first.
    public private(set) var needsYou: [HerdAgent] = []
    public private(set) var workingCount = 0
    public private(set) var sourceStates: [SourceID: SourceState] = [:]
    public private(set) var statusLines: [SourceID: [String]] = [:]
    /// The transitions behind the most recent update that had any.
    public private(set) var lastTransitions: [HerdTransition] = []

    @ObservationIgnored public private(set) var sources: [any AgentSource] = []
    @ObservationIgnored private var bySource: [SourceID: [HerdAgent]] = [:]
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private let log: TransitionLog?

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

    /// Live only when every source is; otherwise the first source's problem, so the user hears
    /// about it.
    public var overallState: SourceState {
        let states = sources.compactMap { sourceStates[$0.id] }
        return states.first { !$0.isLive } ?? (states.isEmpty ? .connecting : .live)
    }

    package func apply(_ update: SourceUpdate, from source: SourceID) {
        bySource[source] = update.agents
        let merged = sources.flatMap { bySource[$0.id] ?? [] }
        if agents != merged { agents = merged }
        let waiting = merged.filter(\.status.needsYou).sorted(by: Self.waitingOrder)
        if needsYou != waiting { needsYou = waiting }
        let working = merged.count { $0.status == .working }
        if workingCount != working { workingCount = working }
        if sourceStates[source] != update.state { sourceStates[source] = update.state }
        if statusLines[source] != update.statusLines { statusLines[source] = update.statusLines }
        if !update.transitions.isEmpty {
            lastTransitions = update.transitions
            if let log { Task { await log.append(update.transitions) } }
        }
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

import AppKit
import HerdrKit
import ShepherdCore

/// herdr as a Shepherd source: adapts `HerdrKit`'s live session to the herd model. The only code
/// that knows both sides.
@MainActor
public final class HerdrSource: AgentSource {
    public static let sourceID: SourceID = "herdr"

    public let id = HerdrSource.sourceID
    public let displayName = "herdr"
    public let capabilities: SourceCapabilities = [.focus]
    public let updates: AsyncStream<SourceUpdate>

    private let continuation: AsyncStream<SourceUpdate>.Continuation
    private let client: HerdrClient
    private let engine: SessionEngine
    private let activatesTerminal: Bool
    private var task: Task<Void, Never>?
    /// Last known kind and project per pane, so a closed agent's transition still says what it was.
    private var known: [String: (kind: String?, project: String)] = [:]

    /// `history` is the transition log; it restores exact times in state across restarts.
    public init(client: HerdrClient = HerdrClient(), history: [HerdTransition] = [],
                debounce: Duration = .milliseconds(100), activatesTerminal: Bool = true) {
        self.client = client
        self.activatesTerminal = activatesTerminal
        engine = SessionEngine(client: client, debounce: debounce, seeds: Self.seeds(from: history))
        (updates, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(16))
    }

    public func start() {
        guard task == nil else { return }
        let engine = engine
        task = Task { [weak self] in
            await engine.start()
            for await update in engine.updates {
                guard let self else { return }
                self.continuation.yield(self.adapt(update))
            }
        }
    }

    public func stop() async {
        task?.cancel()
        task = nil
        await engine.stop()
        continuation.finish()
    }

    public func focus(_ agent: AgentID) async throws {
        try await client.focusAgent(paneID: agent.local)
        if activatesTerminal { activateTerminal() }
    }

    /// The terminal apps hosting an attached herdr client.
    public func hostApplicationPIDs() -> [pid_t] {
        TerminalLocator.hostingApps(
            of: TerminalLocator.pids(named: "herdr"),
            parent: TerminalLocator.parent(of:),
            isApp: { NSRunningApplication(processIdentifier: $0)?.activationPolicy == .regular })
    }

    private func activateTerminal() {
        guard let pid = hostApplicationPIDs().first, let terminal = NSRunningApplication(processIdentifier: pid) else { return }
        NSApp.yieldActivation(to: terminal)
        terminal.activate()
    }

    // MARK: Adapting

    func adapt(_ update: SessionUpdate) -> SourceUpdate {
        let snapshot = update.session.snapshot
        let workspaces = Dictionary(snapshot.workspaces.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let agents = update.session.agents.map { state -> HerdAgent in
            let agent = state.agent
            known[agent.id] = (agent.agent, state.workspaceLabel)
            let workspaceTokens = workspaces[agent.workspaceID]?.tokens ?? [:]
            return HerdAgent(
                id: AgentID(source: id, local: agent.id), kind: agent.agent, name: agent.displayName,
                project: state.workspaceLabel, status: Self.status(agent.status),
                statusLabel: agent.stateLabels[agent.status.rawValue], since: state.since.map(Self.since),
                tokens: workspaceTokens.merging(agent.tokens) { _, own in own },
                isFocusedInSource: agent.id == snapshot.focusedPaneID)
        }
        let transitions = update.transitions.map { transition -> HerdTransition in
            let info = known[transition.paneID]
            let precision = update.session.agent(transition.paneID)?.since?.precision
            return HerdTransition(
                agent: AgentID(source: id, local: transition.paneID), kind: info?.kind, project: info?.project ?? "",
                from: transition.from.map(Self.status), to: transition.to.map(Self.status), at: transition.observedAt,
                precision: precision == .noLaterThan ? .noLaterThan : .exact,
                marker: Self.marker(terminalID: transition.terminalID, seq: transition.stateChangeSeq))
        }
        for transition in update.transitions where transition.kind == .closed { known[transition.paneID] = nil }
        return SourceUpdate(agents: agents, state: Self.state(update.connection),
                            statusLines: Self.statusLines(update), transitions: transitions)
    }

    static func status(_ status: AgentStatus) -> HerdStatus {
        switch status {
        case .idle: .idle
        case .working: .working
        case .blocked: .blocked
        case .done: .done
        case .unknown, .unrecognized: .unknown
        }
    }

    static func since(_ since: StateSince) -> Since {
        Since(since.date, since.precision == .exact ? .exact : .noLaterThan)
    }

    static func state(_ connection: ConnectionState) -> SourceState {
        switch connection {
        case .connecting: .connecting
        case .live: .live
        case .stale(let reason): .stale(reason)
        case .disconnected(let reason): .disconnected(reason)
        }
    }

    static func statusLines(_ update: SessionUpdate) -> [String] {
        var lines: [String] = []
        if update.connection.isLive { lines.append("herdr \(update.session.snapshot.version)") }
        switch update.compatibility {
        case .matched: break
        case .older(let value): lines.append("herdr protocol \(value) is older than tested (\(HerdrProtocol.tested))")
        case .newer(let value): lines.append("herdr protocol \(value) is newer than tested (\(HerdrProtocol.tested))")
        }
        return lines
    }

    // MARK: Restart markers

    /// `<terminal id>|<state change seq>`: if both still match after a restart, the agent has not
    /// changed state since the transition was logged.
    static func marker(terminalID: String?, seq: UInt64) -> String {
        "\(terminalID ?? "")|\(seq)"
    }

    static func seeds(from history: [HerdTransition]) -> [TransitionTracker.Seed] {
        var latest: [String: HerdTransition] = [:]
        for entry in history where entry.agent.source == sourceID { latest[entry.agent.local] = entry }
        return latest.values.compactMap { entry in
            guard entry.to != nil, let marker = entry.marker,
                  let separator = marker.lastIndex(of: "|"),
                  let seq = UInt64(marker[marker.index(after: separator)...]) else { return nil }
            let terminal = String(marker[..<separator])
            return TransitionTracker.Seed(
                paneID: entry.agent.local, terminalID: terminal.isEmpty ? nil : terminal, stateChangeSeq: seq,
                since: StateSince(entry.at, entry.precision == .exact ? .exact : .noLaterThan))
        }
    }
}

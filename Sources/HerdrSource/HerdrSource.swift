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
    public let capabilities: SourceCapabilities = [.focus, .focusProject]
    public let updates: AsyncStream<SourceUpdate>

    private let continuation: AsyncStream<SourceUpdate>.Continuation
    private let client: HerdrClient
    private let engine: SessionEngine
    private let activatesTerminal: Bool
    private var task: Task<Void, Never>?
    /// Last known kind and project per pane, so a closed agent's transition still says what it was.
    private var known: [String: (kind: String?, project: String)] = [:]
    /// herdr's config file, read for its sidebar token layout; nil to not read one.
    private let configURL: URL?
    private var configWatcher: FileWatcher?
    private var sidebar: (layout: TokenLayout?, problems: [String]) = (nil, [])
    /// The last update sent and its connection lines, so a change to herdr's config can be re-sent
    /// without a new snapshot.
    private var lastSent: (update: SourceUpdate, connectionLines: [String])?

    /// `history` is the transition log; it restores exact times in state across restarts.
    public init(client: HerdrClient = HerdrClient(), history: [HerdTransition] = [],
                debounce: Duration = .milliseconds(100), activatesTerminal: Bool = true,
                configURL: URL? = HerdrSidebar.configURL()) {
        self.client = client
        self.activatesTerminal = activatesTerminal
        self.configURL = configURL
        engine = SessionEngine(client: client, debounce: debounce, seeds: Self.seeds(from: history))
        (updates, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(16))
    }

    public func start() {
        guard task == nil else { return }
        watchConfig()
        let engine = engine
        task = Task { [weak self] in
            await engine.start()
            for await update in engine.updates {
                guard let self else { return }
                let lines = self.statusLines(update)
                let adapted = self.adapt(update, connectionLines: lines)
                self.lastSent = (adapted, lines)
                self.continuation.yield(adapted)
            }
        }
    }

    public func stop() async {
        configWatcher?.stop()
        configWatcher = nil
        task?.cancel()
        task = nil
        await engine.stop()
        continuation.finish()
    }

    public func focus(_ agent: AgentID) async throws {
        try await client.focusAgent(paneID: agent.local)
        if activatesTerminal { activateTerminal() }
    }

    public func focusProject(_ project: ProjectID) async throws {
        try await client.focusWorkspace(id: project.local)
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

    // MARK: herdr's config

    private func watchConfig() {
        guard let configURL else { return }
        let data = try? Data(contentsOf: configURL)
        sidebar = HerdrSidebar.read(data)
        let watcher = FileWatcher(url: configURL) { [weak self] data in
            Task { @MainActor in self?.configChanged(data) }
        }
        configWatcher = watcher
        watcher.start(known: data)
    }

    func configChanged(_ data: Data?) {
        let read = HerdrSidebar.read(data)
        guard read.layout != sidebar.layout || read.problems != sidebar.problems else { return }
        sidebar = read
        guard let (last, lines) = lastSent else { return }
        // Same herd, new styling; the transitions were already sent.
        let update = SourceUpdate(agents: last.agents, projects: last.projects, state: last.state,
                                  statusLines: lines + sidebar.problems, tokenLayout: sidebar.layout)
        lastSent = (update, lines)
        continuation.yield(update)
    }

    // MARK: Adapting

    func adapt(_ update: SessionUpdate, connectionLines: [String]) -> SourceUpdate {
        let snapshot = update.session.snapshot
        let projects = snapshot.workspaces.map { workspace in
            HerdProject(id: ProjectID(source: id, local: workspace.id), name: workspace.label, tokens: workspace.tokens,
                        isFocusedInSource: workspace.focused || workspace.id == snapshot.focusedWorkspaceID)
        }
        let agents = update.session.agents.map { state -> HerdAgent in
            let agent = state.agent
            known[agent.id] = (agent.agent, state.workspaceLabel)
            return HerdAgent(
                id: AgentID(source: id, local: agent.id), kind: agent.agent, name: agent.displayName,
                projectID: ProjectID(source: id, local: agent.workspaceID), project: state.workspaceLabel,
                status: Self.status(agent.status), statusLabel: agent.stateLabels[agent.status.rawValue],
                since: state.since.map(Self.since), tokens: agent.tokens,
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
        return SourceUpdate(agents: agents, projects: projects, state: Self.state(update.connection),
                            statusLines: connectionLines + sidebar.problems, transitions: transitions,
                            tokenLayout: sidebar.layout)
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

    func statusLines(_ update: SessionUpdate) -> [String] {
        var lines: [String] = []
        if update.connection.isLive {
            lines.append("herdr \(update.session.snapshot.version)")
        } else {
            lines.append("herdr socket: \(client.socketPath)")
        }
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

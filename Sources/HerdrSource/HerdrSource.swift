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
    public let capabilities: SourceCapabilities = [.focus, .focusProject, .readOutput, .sendKeys, .sendText, .prompt,
                                                       .createWorktree, .startAgent]
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
    /// herdr's `ui.toast.delivery` reaches system notifications.
    private var postsSystemAlerts = false
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

    /// A herdr on another socket, such as demo mode's fake one: no history, no terminal to bring
    /// forward and no herdr config read.
    public convenience init(socketPath: String) {
        self.init(client: HerdrClient(socketPath: socketPath), activatesTerminal: false, configURL: nil)
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

    public func read(_ agent: AgentID, lines: Int) async throws -> String {
        try await readable { try await client.readAgent(paneID: agent.local, lines: lines) }
    }

    public func sendKeys(_ agent: AgentID, _ keys: [String]) async throws {
        try await readable { try await client.sendKeys(paneID: agent.local, keys: keys) }
    }

    public func sendText(_ agent: AgentID, _ text: String) async throws {
        try await readable { try await client.sendInput(paneID: agent.local, text: text, keys: ["enter"]) }
    }

    public func prompt(_ agent: AgentID, _ text: String) async throws {
        try await readable { try await client.promptAgent(paneID: agent.local, text: text) }
    }

    /// `worktree.create` from the project's workspace, `agent.start` in its shell pane, then
    /// `agent.prompt`. A later step that fails says what the earlier ones left behind, so the
    /// user can clean up or carry on in herdr.
    public func startTask(_ task: NewTask, args: [String]) async throws -> AgentID {
        let created = try await readable { try await client.createWorktree(workspaceID: task.project.local, branch: task.branch) }
        let place = created.branch.map { "worktree \($0)" } ?? "the new worktree"
        do {
            try await client.startAgent(name: Self.agentName(kind: task.kind), kind: task.kind, paneID: created.rootPaneID, args: args)
        } catch let error as HerdrError {
            throw AgentSourceError.failed("Created \(place), but \(task.kind) did not start: \(Self.describe(error))")
        }
        let agent = AgentID(source: id, local: created.rootPaneID)
        guard !task.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return agent }
        do {
            try await client.promptAgent(paneID: created.rootPaneID, text: task.prompt)
        } catch let error as HerdrError {
            throw AgentSourceError.failed("Started \(task.kind) in \(place), but the prompt did not go through: \(Self.describe(error))")
        }
        return agent
    }

    /// A unique name in herdr's rules: lowercase, starting with a letter, at most 32 characters.
    static func agentName(kind: String) -> String {
        let base = String(kind.lowercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }.prefix(20))
        let suffix = String(UInt32.random(in: 0..<UInt32.max), radix: 36)
        return (base.first?.isLetter == true ? base : "agent") + "-" + suffix
    }

    /// Runs a call, turning herdr's errors into words for the surface that shows them.
    private func readable<T>(_ call: () async throws -> T) async throws -> T {
        do {
            return try await call()
        } catch let error as HerdrError {
            throw AgentSourceError.failed(Self.describe(error))
        }
    }

    static func describe(_ error: HerdrError) -> String {
        switch error {
        case .notRunning: "herdr is not running"
        case .permissionDenied: "no permission to use herdr's socket"
        case .timeout: "herdr did not answer in time"
        case .disconnected: "herdr closed the connection"
        case .server(_, let message): "herdr: \(message)"
        case .socketPathTooLong, .lineTooLong, .io, .unexpectedResponse: "herdr: \(error)"
        }
    }

    /// The terminal apps hosting an attached herdr client (see `HerdrProcesses`).
    public func hostApplicationPIDs() -> [pid_t] {
        TerminalLocator.hostingApps(
            of: HerdrProcesses.pids(named: "herdr"),
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
        postsSystemAlerts = HerdrSidebar.postsSystemAlerts(data)
        let watcher = FileWatcher(url: configURL) { [weak self] data in
            Task { @MainActor in self?.configChanged(data) }
        }
        configWatcher = watcher
        watcher.start(known: data)
    }

    func configChanged(_ data: Data?) {
        let read = HerdrSidebar.read(data)
        let alerts = HerdrSidebar.postsSystemAlerts(data)
        guard read.layout != sidebar.layout || read.problems != sidebar.problems || alerts != postsSystemAlerts else { return }
        sidebar = read
        postsSystemAlerts = alerts
        guard let (last, lines) = lastSent else { return }
        // Same herd, new styling; the transitions were already sent.
        let update = SourceUpdate(agents: last.agents, projects: last.projects, state: last.state,
                                  statusLines: lines + sidebar.problems, tokenLayout: sidebar.layout,
                                  postsSystemAlerts: postsSystemAlerts)
        lastSent = (update, lines)
        continuation.yield(update)
    }

    // MARK: Adapting

    func adapt(_ update: SessionUpdate, connectionLines: [String]) -> SourceUpdate {
        let snapshot = update.session.snapshot
        let projects = snapshot.workspaces.map { workspace in
            HerdProject(id: ProjectID(source: id, local: workspace.id), name: workspace.label, tokens: workspace.tokens,
                        isFocusedInSource: workspace.focused || workspace.id == snapshot.focusedWorkspaceID,
                        repo: workspace.worktree.map { HerdRepo(key: $0.repoKey, name: $0.repoName, isLinkedCheckout: $0.isLinked) },
                        path: workspace.worktree?.checkoutPath)
        }
        let agents = update.session.agents.map { state -> HerdAgent in
            let agent = state.agent
            known[agent.id] = (agent.agent, state.workspaceLabel)
            return HerdAgent(
                id: AgentID(source: id, local: agent.id), kind: agent.agent, name: agent.displayName,
                projectID: ProjectID(source: id, local: agent.workspaceID), project: state.workspaceLabel,
                status: Self.status(agent.status), statusLabel: agent.stateLabels[agent.status.rawValue],
                since: state.since.map(Self.since), tokens: agent.tokens,
                isFocusedInSource: agent.id == snapshot.focusedPaneID, session: Self.session(agent))
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
        let state = state(update.connection)
        // A herdr that is gone has no panes: its last agents are not kept, even dimmed, so nothing
        // counts them as waiting.
        if state.isAbsent {
            return SourceUpdate(agents: [], projects: [], state: state, statusLines: connectionLines + sidebar.problems,
                                transitions: transitions, tokenLayout: sidebar.layout, postsSystemAlerts: postsSystemAlerts)
        }
        return SourceUpdate(agents: agents, projects: projects, state: state,
                            statusLines: connectionLines + sidebar.problems, transitions: transitions,
                            tokenLayout: sidebar.layout, postsSystemAlerts: postsSystemAlerts)
    }

    /// The agent's own session, when herdr reports its id.
    static func session(_ agent: Agent) -> AgentSession? {
        guard let session = agent.session, session.kind == "id", let id = session.value, !id.isEmpty,
              let kind = session.agent ?? agent.agent else { return nil }
        return AgentSession(kind: kind, id: id, cwd: agent.cwd)
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

    /// Without a socket file there is no herdr session at all (not installed, or not started), which
    /// is not a problem for someone who does not use herdr. A socket left behind by a herdr that
    /// crashed is still a disconnection.
    func state(_ connection: ConnectionState) -> SourceState {
        switch connection {
        case .connecting: .connecting
        case .live: .live
        case .stale(let reason): .stale(reason)
        case .disconnected(let reason): socketExists ? .disconnected(reason) : .absent("herdr is not running")
        }
    }

    private var socketExists: Bool { FileManager.default.fileExists(atPath: client.socketPath) }

    func statusLines(_ update: SessionUpdate) -> [String] {
        var lines: [String] = []
        if update.connection.isLive {
            lines.append("herdr \(update.session.snapshot.version)")
        } else if case .disconnected = update.connection, !socketExists {
            lines.append("herdr is not running")
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

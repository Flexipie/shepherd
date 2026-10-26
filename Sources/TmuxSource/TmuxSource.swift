import AppKit
import Foundation
import ShepherdCore
import TmuxKit

/// tmux as a Shepherd source: a pane whose process tree runs a known agent is an agent. Its state
/// comes from the pane's screen, so it is labelled inferred, and a report from the same pane wins
/// (`HerdStore`). Nothing polls: a control-mode client per server says when a pane printed, and the
/// socket folder says when a server came or went.
@MainActor
public final class TmuxSource: AgentSource {
    public static let sourceID: SourceID = PaneTracker.source
    /// A pane's screen is read this long after its first output. Output in the meantime waits for that read.
    static let readDelay: Duration = .milliseconds(300)
    /// Window and session changes are listed this long after the first one.
    static let listDelay: Duration = .milliseconds(300)
    /// Output from a pane that is not an agent yet waits longer: an agent may have just started there.
    static let newPaneDelay: Duration = .seconds(1)

    public let id = TmuxSource.sourceID
    public let displayName = "tmux"
    /// Reads the screen, so it can show and send to the agent. It cannot start one: that needs a
    /// worktree, which comes in the next step.
    public let capabilities: SourceCapabilities = [.focus, .readOutput, .sendKeys, .sendText, .prompt]
    public let updates: AsyncStream<SourceUpdate>

    private let continuation: AsyncStream<SourceUpdate>.Continuation
    private let binary: String
    private let directory: URL
    private let activatesTerminal: Bool
    /// How each agent kind is found and read; replaced when the config changes.
    private var patterns: [String: ScreenPatterns]
    private var screens: ScreenStatus
    private var watcher: TmuxSocketWatcher?
    /// Control clients, by socket path.
    private var controls: [String: Control] = [:]
    /// Sockets whose control client ended while their server was still up. Not restarted until the
    /// server is gone, so a client that cannot attach does not restart on every listing.
    private var detached: Set<String> = []
    private var observations: [String: PaneObservation] = [:]
    private var tracker = PaneTracker()
    /// The terminals' clients: Shepherd's own control clients are left out.
    private var clients: [TmuxAttachedClient] = []
    private var serverCount = 0
    private var reads: [String: Task<Void, Never>] = [:]
    private var listing: Task<Void, Never>?
    private var deadline: Task<Void, Never>?
    /// Listings are numbered as they start. One that finishes after a newer one is dropped.
    private var lastRequested = 0
    private var lastApplied = 0

    private struct Control {
        let client: ControlClient
        /// Tells a client that ended apart from its replacement.
        let token: UUID
    }

    /// Nil when tmux is not installed: the source is then not added at all.
    public init?(binary: String? = TmuxClient.locate(), directory: URL = TmuxSockets.directory(),
                 activatesTerminal: Bool = true, screens: [String: ScreenPatterns] = ScreenPatterns.builtin) {
        guard let binary else { return nil }
        self.binary = binary
        self.directory = directory
        self.activatesTerminal = activatesTerminal
        patterns = screens
        self.screens = ScreenStatus(screens)
        (updates, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(16))
    }

    public func start() {
        guard watcher == nil else { return }
        let watcher = TmuxSocketWatcher(directory: directory) { [weak self] in
            Task { @MainActor in self?.scheduleList(after: Self.listDelay) }
        }
        self.watcher = watcher
        watcher.start()
        scheduleList(after: .zero)
    }

    /// Uses new screen patterns: every pane is listed and read again with them.
    public func setScreens(_ patterns: [String: ScreenPatterns]) {
        guard patterns != self.patterns else { return }
        self.patterns = patterns
        screens = ScreenStatus(patterns)
        // A listing reads `screens` when it runs, so one already waiting covers this.
        if watcher != nil { scheduleList(after: .zero) }
    }

    public func stop() async {
        watcher?.stop()
        watcher = nil
        listing?.cancel()
        listing = nil
        deadline?.cancel()
        deadline = nil
        for task in reads.values { task.cancel() }
        reads = [:]
        let running = controls.values.map(\.client)
        controls = [:]
        for client in running { await client.stop() }
        continuation.finish()
    }

    // MARK: Actions

    public func focus(_ agent: AgentID) async throws {
        let pane = try target(agent)
        let client = TmuxClient(binary: binary, socket: pane.socket)
        try await tmux {
            try client.selectWindow(pane.windowID)
            try client.selectPane(pane.paneID)
        }
        if activatesTerminal { activateTerminal(session: pane.session) }
    }

    public func read(_ agent: AgentID, lines: Int) async throws -> String {
        let pane = try target(agent)
        let client = TmuxClient(binary: binary, socket: pane.socket)
        return try await tmux { try client.history(pane.paneID, lines: lines) }
    }

    public func sendKeys(_ agent: AgentID, _ keys: [String]) async throws {
        let pane = try target(agent)
        let client = TmuxClient(binary: binary, socket: pane.socket)
        try await tmux { try client.sendKeys(pane.paneID, keys) }
    }

    public func sendText(_ agent: AgentID, _ text: String) async throws {
        let pane = try target(agent)
        let client = TmuxClient(binary: binary, socket: pane.socket)
        try await tmux {
            try client.sendLiteral(pane.paneID, text)
            try client.sendKeys(pane.paneID, ["enter"])
        }
    }

    /// Only to an agent that shows as idle: a prompt typed into a running turn would go to the wrong place.
    public func prompt(_ agent: AgentID, _ text: String) async throws {
        guard tracker.shown(agent.local) == .idle else { throw AgentSourceError.failed("the agent is not idle") }
        try await sendText(agent, text)
    }

    /// The terminals attached to the servers. Used to tell whether the user is already looking at an agent.
    public func hostApplicationPIDs() -> [pid_t] {
        Self.hostingApps(of: clients.map(\.pid))
    }

    /// Brings forward the terminal of a client on the agent's session, or of any client if none is on it.
    private func activateTerminal(session: String) {
        let onSession = clients.filter { $0.session == session }.map(\.pid)
        let pids = onSession.isEmpty ? clients.map(\.pid) : onSession
        guard let pid = Self.hostingApps(of: pids).first, let terminal = NSRunningApplication(processIdentifier: pid) else { return }
        NSApp.yieldActivation(to: terminal)
        terminal.activate()
    }

    private static func hostingApps(of pids: [pid_t]) -> [pid_t] {
        TerminalLocator.hostingApps(
            of: pids,
            parent: TerminalLocator.parent(of:),
            isApp: { NSRunningApplication(processIdentifier: $0)?.activationPolicy == .regular })
    }

    private func target(_ agent: AgentID) throws -> PaneObservation {
        guard let observation = observations[agent.local] else {
            throw AgentSourceError.failed("that agent is no longer in tmux")
        }
        return observation
    }

    /// Runs a tmux call off the main actor and says a failure in words.
    private func tmux<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        do {
            return try await Task.detached(priority: .userInitiated, operation: work).value
        } catch let error as TmuxError {
            throw AgentSourceError.failed(error.description)
        }
    }

    // MARK: Listing

    /// Lists the servers after `delay`. A listing already waiting covers this request.
    private func scheduleList(after delay: Duration) {
        guard listing == nil else { return }
        listing = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            self.listing = nil
            await self.list()
        }
    }

    private func list() async {
        lastRequested += 1
        let generation = lastRequested
        let binary = binary
        let directory = directory
        let screens = screens
        let scan = await Task.detached(priority: .utility) {
            TmuxScan.run(binary: binary, directory: directory, screens: screens)
        }.value
        guard generation > lastApplied else { return }
        lastApplied = generation
        apply(scan, at: Date())
    }

    private func apply(_ scan: TmuxScan, at now: Date) {
        serverCount = scan.servers.count
        let live = Set(scan.servers.map(\.socket))
        for socket in controls.keys.filter({ !live.contains($0) }) { stopControl(socket) }
        detached.formIntersection(live)
        let attaching = live.filter { controls[$0] == nil && !detached.contains($0) }
        for socket in attaching { startControl(socket) }

        clients = scan.servers.flatMap(\.clients).filter { !$0.isControl }
        var current: [String: PaneObservation] = [:]
        for agent in scan.agents {
            let pane = agent.pane
            let key = PaneObservation.key(socket: pane.socket, paneID: pane.paneID)
            current[key] = PaneObservation(
                key: key, socket: pane.socket, paneID: pane.paneID, windowID: pane.windowID, session: pane.session,
                kind: agent.kind, path: pane.path, checkout: agent.checkout,
                isFocused: pane.isActive && clients.contains { $0.session == pane.session },
                status: agent.status, workingSeen: agent.status == .working ? now : nil)
        }
        observations = current
        publish(at: now)
        // Output printed before a new control client attached is never sent to it. One more listing,
        // once it is attached, reads those screens.
        if !attaching.isEmpty { scheduleList(after: Self.listDelay) }
    }

    // MARK: Control clients

    private func startControl(_ socket: String) {
        let client = ControlClient(binary: binary, socket: socket)
        let token = UUID()
        controls[socket] = Control(client: client, token: token)
        Task {
            do {
                try await client.start(events: { [weak self] event in
                    Task { @MainActor in self?.control(event, socket: socket) }
                }, ended: { [weak self] in
                    Task { @MainActor in self?.controlEnded(socket, token: token) }
                })
            } catch {
                controlEnded(socket, token: token)
            }
        }
    }

    private func stopControl(_ socket: String) {
        guard let control = controls.removeValue(forKey: socket) else { return }
        Task { await control.client.stop() }
    }

    private func control(_ event: ControlEvent, socket: String) {
        switch event {
        case .output(let pane):
            let key = PaneObservation.key(socket: socket, paneID: pane)
            if observations[key] != nil { scheduleRead(key) } else { scheduleList(after: Self.newPaneDelay) }
        case .layout:
            scheduleList(after: Self.listDelay)
        case .exit, .other:
            break
        }
    }

    private func controlEnded(_ socket: String, token: UUID) {
        guard controls[socket]?.token == token else { return }
        controls[socket] = nil
        detached.insert(socket)
        scheduleList(after: Self.listDelay)
    }

    // MARK: Screen reads

    /// Reads one pane's screen after `readDelay`. A read already waiting covers the output too.
    private func scheduleRead(_ key: String) {
        guard reads[key] == nil else { return }
        reads[key] = Task { [weak self] in
            try? await Task.sleep(for: Self.readDelay)
            guard !Task.isCancelled, let self else { return }
            self.reads[key] = nil
            await self.readScreen(key)
        }
    }

    private func readScreen(_ key: String) async {
        guard let observation = observations[key] else { return }
        let client = TmuxClient(binary: binary, socket: observation.socket)
        let pane = observation.paneID
        let kind = observation.kind
        let screens = screens
        // Patterns come from config, so they are matched off the main actor too.
        let status = await Task.detached(priority: .utility) {
            (try? client.screen(pane)).map { screens.status(kind: kind, screen: $0) }
        }.value
        guard let status else {
            // The pane or its server is gone; a listing says which.
            scheduleList(after: Self.listDelay)
            return
        }
        guard observations[key] != nil else { return }
        let now = Date()
        observations[key]?.status = status
        observations[key]?.workingSeen = status == .working ? now : nil
        publish(at: now)
    }

    // MARK: Publishing

    private func publish(at now: Date) {
        let outcome = tracker.apply(Array(observations.values), at: now)
        let servers = serverCount == 0 ? "no tmux server running" : "\(serverCount) tmux server\(serverCount == 1 ? "" : "s")"
        continuation.yield(SourceUpdate(agents: outcome.agents, projects: outcome.projects, state: .live,
                                        statusLines: [servers], transitions: outcome.transitions))
        scheduleDeadline(outcome.nextDeadline, now: now)
    }

    /// One sleep until the next pending change settles or a working reading goes stale. Replaces any earlier one.
    private func scheduleDeadline(_ date: Date?, now: Date) {
        deadline?.cancel()
        deadline = nil
        guard let date else { return }
        let delay = max(0, date.timeIntervalSince(now))
        deadline = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.publish(at: Date())
        }
    }
}

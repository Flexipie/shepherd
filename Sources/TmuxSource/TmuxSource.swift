import AppKit
import Foundation
import ShepherdCore
import TmuxKit

/// tmux as a Shepherd source: a pane whose process tree runs a known agent is an agent. Its state
/// comes from the pane's screen, so it is labelled inferred, and a report from the same pane wins
/// (`HerdStore`). Nothing polls: a control-mode client per server says when a pane printed (its own
/// session's output, and a subscription for the rest, `TmuxFollow`), and the socket folder says
/// when a server came or went.
@MainActor
public final class TmuxSource: AgentSource {
    public static let sourceID: SourceID = PaneTracker.source
    /// A pane's screen is read this long after its first output. Output in the meantime waits for that read.
    static let readDelay: Duration = .milliseconds(300)
    /// Window and session changes are listed this long after the first one.
    static let listDelay: Duration = .milliseconds(300)
    /// Output from a pane that is not an agent yet waits longer: an agent may have just started there.
    static let newPaneDelay: Duration = .seconds(1)
    /// One more read after a pane the subscription reported changed (`scheduleFollowUp`).
    static let followUpDelay: Duration = .milliseconds(1100)
    /// Output from a pane a listing already saw without an agent: a log or a dev server in any
    /// session prints all the time, so it lists rarely. An agent started in that shell shows this late.
    static let shellPaneDelay: Duration = .seconds(5)

    public let id = TmuxSource.sourceID
    public let displayName = "tmux"
    /// Reads the screen, so it can show and send to the agent, and starts tasks in a new window.
    public let capabilities: SourceCapabilities = [.focus, .readOutput, .sendKeys, .sendText, .prompt, .createWorktree, .startAgent]
    public let updates: AsyncStream<SourceUpdate>

    private let continuation: AsyncStream<SourceUpdate>.Continuation
    private let binary: String
    private let directory: URL
    private let activatesTerminal: Bool
    /// How each agent kind is found and read; replaced when the config changes.
    private var patterns: [String: ScreenPatterns]
    private var screens: ScreenStatus
    private var watcher: TmuxSocketWatcher?
    /// Control clients, one per server, by socket (`TmuxFollow`).
    private var controls: [String: Control] = [:]
    /// Sessions whose control client ended before it ever attached, by socket. Not chosen again
    /// until the session is gone, so a client that cannot attach does not restart on every listing.
    /// One that attached and was then detached (`tmux attach -d` detaches every other client) is.
    private var failed: [String: Set<String>] = [:]
    /// Each server's last subscription value: every pane's signature (`TmuxActivity`).
    private var activity: [String: [String: String]] = [:]
    private var observations: [String: PaneObservation] = [:]
    /// Panes a task started that no scan has shown as an agent yet, by key, so the new agent's
    /// stage can read and jump to it at once. `listing` is the last listing requested when it
    /// started: only a later one can have seen the pane.
    private var started: [String: (socket: String, paneID: String, session: String, listing: Int)] = [:]
    private var tracker = PaneTracker()
    /// The terminals' clients: Shepherd's own control clients are left out.
    private var clients: [TmuxAttachedClient] = []
    private var serverCount = 0
    private var reads: [String: Task<Void, Never>] = [:]
    private var followUps: [String: Task<Void, Never>] = [:]
    private var listing: Task<Void, Never>?
    /// When the waiting listing runs.
    private var listingAt: ContinuousClock.Instant?
    /// Every pane the last listing saw, agent or not (`TmuxScan.panes`).
    private var listedPanes: Set<String> = []
    private var deadline: Task<Void, Never>?
    /// Listings are numbered as they start. One that finishes after a newer one is dropped.
    private var lastRequested = 0
    private var lastApplied = 0

    private struct Control {
        let client: ControlClient
        /// Tells a client that ended apart from its replacement.
        let token: UUID
        var choice: TmuxFollow.Choice
        /// tmux has sent it something, so it did attach.
        var attached = false
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
        listingAt = nil
        deadline?.cancel()
        deadline = nil
        for task in reads.values { task.cancel() }
        reads = [:]
        for task in followUps.values { task.cancel() }
        followUps = [:]
        let running = controls.values.map(\.client)
        controls = [:]
        for client in running { await client.stop() }
        continuation.finish()
    }

    // MARK: Actions

    public func focus(_ agent: AgentID) async throws {
        let pane = try pane(agent)
        let client = TmuxClient(binary: binary, socket: pane.socket)
        // A pane id names its window too, so a pane no scan has listed yet can be shown.
        try await tmux {
            try client.selectWindow(pane.paneID)
            try client.selectPane(pane.paneID)
        }
        if activatesTerminal { activateTerminal(session: observations[agent.local]?.session ?? started[agent.local]?.session) }
    }

    public func read(_ agent: AgentID, lines: Int) async throws -> String {
        let pane = try pane(agent)
        let client = TmuxClient(binary: binary, socket: pane.socket)
        return try await tmux { try client.history(pane.paneID, lines: lines) }
    }

    public func sendKeys(_ agent: AgentID, _ keys: [String]) async throws {
        let pane = try pane(agent)
        let client = TmuxClient(binary: binary, socket: pane.socket)
        try await tmux { try client.sendKeys(pane.paneID, keys) }
    }

    public func sendText(_ agent: AgentID, _ text: String) async throws {
        let pane = try pane(agent)
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

    /// `git worktree add` off the project's checkout, then a window in the session of one of its
    /// agents running the agent with the prompt as its first argument, so it waits through anything
    /// the agent asks first (`TmuxNewTask.command`). A step that fails after the worktree was made
    /// says it is there.
    public func startTask(_ task: NewTask, args: [String]) async throws -> AgentID {
        let panes = observations.values.filter { $0.projectPath == task.project.local }.sorted { $0.key < $1.key }
        guard let pane = panes.first(where: \.isFocused) ?? panes.first else {
            throw AgentSourceError.failed("that project is no longer in tmux")
        }
        guard let checkout = pane.checkout else {
            throw AgentSourceError.failed("\(PaneTracker.projectName(pane.projectPath)) is not in a git repo, so there is no worktree to make")
        }
        let branch = task.branch ?? TmuxNewTask.branchName(kind: task.kind)
        let folder = TmuxNewTask.folder(for: checkout, branch: branch)
        let command = TmuxNewTask.command(kind: task.kind, args: args, prompt: task.prompt)
        // Checked before anything is made, so a refusal leaves nothing behind.
        if let problem = TmuxNewTask.tooLong(command) { throw AgentSourceError.failed(problem) }
        guard !FileManager.default.fileExists(atPath: folder) else {
            throw AgentSourceError.failed("\(folder) already exists; pick another branch name")
        }
        let client = TmuxClient(binary: binary, socket: pane.socket)
        // Shepherd's own PATH is short when it was opened from Finder; the server's is the user's.
        // The window runs with it, so the agent must be found on it, else the window would only say
        // "command not found" while the task looked started.
        let kind = task.kind
        let (path, git, agent) = await Task.detached {
            let path = client.globalEnvironment("PATH")
            let search = path ?? ProcessInfo.processInfo.environment["PATH"] ?? ""
            return (path, TmuxNewTask.locateGit(path: search), TmuxNewTask.executable(kind, in: search))
        }.value
        guard let git else { throw AgentSourceError.failed("git is not installed") }
        guard agent != nil else { throw AgentSourceError.failed("\(kind) is not on tmux's PATH") }
        try await tmux { try TmuxNewTask.addWorktree(git: git, checkout: checkout.root, branch: branch, folder: folder, path: path) }
        let paneID: String
        do {
            paneID = try await tmux { try client.newWindow(after: pane.windowID, folder: folder, name: branch, path: path, command: command) }
        } catch {
            throw AgentSourceError.failed("Created worktree \(branch) at \(folder), but \(task.kind) did not start: \(error)")
        }
        let key = PaneObservation.key(socket: pane.socket, paneID: paneID)
        started[key] = (pane.socket, paneID, pane.session, lastRequested)
        return AgentID(source: id, local: key)
    }

    /// The terminals attached to the servers. Used to tell whether the user is already looking at an agent.
    public func hostApplicationPIDs() -> [pid_t] {
        Self.hostingApps(of: clients.map(\.pid))
    }

    /// Brings forward the terminal of a client on the agent's session, or of any client if none is on it.
    private func activateTerminal(session: String?) {
        let onSession = clients.filter { $0.session == session }.map(\.pid)
        let pids = onSession.isEmpty ? clients.map(\.pid) : onSession
        guard let pid = Self.hostingApps(of: pids).first, let terminal = NSRunningApplication(processIdentifier: pid) else { return }
        NSApp.yieldActivation(to: terminal)
        terminal.activate()
    }

    private static func hostingApps(of pids: [pid_t]) -> [pid_t] {
        TerminalLocator.hostingApps(
            of: pids,
            isApp: { NSRunningApplication(processIdentifier: $0)?.activationPolicy == .regular })
    }

    /// Where an agent's pane is: a listed agent, or one a task just started.
    private func pane(_ agent: AgentID) throws -> (socket: String, paneID: String) {
        if let observation = observations[agent.local] { return (observation.socket, observation.paneID) }
        guard let pane = started[agent.local] else { throw AgentSourceError.failed("that agent is no longer in tmux") }
        return (pane.socket, pane.paneID)
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

    /// Lists the servers after `delay`. A listing already waiting covers this request, unless this
    /// one is due sooner: the listing then moves up.
    private func scheduleList(after delay: Duration) {
        // A control client's last events can arrive after `stop`.
        guard watcher != nil else { return }
        let at = ContinuousClock.now + delay
        if let listingAt, listingAt <= at { return }
        listing?.cancel()
        listingAt = at
        listing = Task { [weak self] in
            try? await Task.sleep(until: at)
            guard !Task.isCancelled, let self else { return }
            self.listing = nil
            self.listingAt = nil
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
        // Stopped while it scanned: attaching now would leave clients behind.
        guard watcher != nil, generation > lastApplied else { return }
        lastApplied = generation
        apply(scan, at: Date())
    }

    private func apply(_ scan: TmuxScan, at now: Date) {
        serverCount = scan.servers.count
        let live = Set(scan.servers.map(\.socket))
        for socket in controls.keys.filter({ !live.contains($0) }) { stopControl(socket) }
        failed = failed.filter { live.contains($0.key) }
        var attaching = false
        for server in scan.servers {
            let socket = server.socket
            failed[socket]?.formIntersection(server.sessions.map(\.id))
            let sessions = server.sessions.filter { !(failed[socket]?.contains($0.id) ?? false) }
            let choice = TmuxFollow.choose(sessions: sessions, terminals: server.clients.filter { !$0.isControl },
                                           current: controls[socket]?.choice)
            if let choice, controls[socket]?.choice.session == choice.session {
                controls[socket]?.choice = choice
                continue
            }
            stopControl(socket)
            if let choice {
                startControl(socket, choice)
                attaching = true
            }
        }

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
        listedPanes = scan.panes
        // A started pane stops being one once a later scan lists it as an agent, or not at all.
        started = started.filter { key, pane in
            pane.listing >= lastApplied || (current[key] == nil && scan.panes.contains(key))
        }
        publish(at: now)
        // Output printed before a new control client attached is never sent to it. One more listing,
        // once it is attached, reads those screens.
        if attaching { scheduleList(after: Self.listDelay) }
    }

    // MARK: Control clients

    private func startControl(_ socket: String, _ choice: TmuxFollow.Choice) {
        let client = ControlClient(binary: binary, socket: socket, session: choice.session)
        let token = UUID()
        controls[socket] = Control(client: client, token: token, choice: choice)
        activity[socket] = nil
        Task {
            // Dropped or stopped before it started.
            guard controls[socket]?.token == token else { return }
            do {
                try await client.start(events: { [weak self] event in
                    Task { @MainActor in self?.control(event, socket: socket, token: token) }
                }, ended: { [weak self] in
                    Task { @MainActor in self?.controlEnded(socket, token: token) }
                })
                await client.subscribe(TmuxActivity.subscription, format: TmuxActivity.format)
            } catch {
                controlEnded(socket, token: token)
            }
        }
    }

    private func stopControl(_ socket: String) {
        activity[socket] = nil
        guard let control = controls.removeValue(forKey: socket) else { return }
        Task { await control.client.stop() }
    }

    private func control(_ event: ControlEvent, socket: String, token: UUID) {
        guard controls[socket]?.token == token else { return }
        // tmux says `%session-changed` once attached; a failed attach sends only command replies and `%exit`.
        if event != .exit, event != .other { controls[socket]?.attached = true }
        switch event {
        case .output(let pane):
            changed(PaneObservation.key(socket: socket, paneID: pane), subscribed: false)
        case .subscription(let name, let value) where name == TmuxActivity.subscription:
            let panes = TmuxActivity.parse(value)
            let before = activity[socket]
            activity[socket] = panes
            // The first value is where the panes stand; the listing after attaching reads them.
            guard let before else { return }
            for pane in TmuxActivity.changed(from: before, to: panes) {
                changed(PaneObservation.key(socket: socket, paneID: pane), subscribed: true)
            }
        case .layout:
            scheduleList(after: Self.listDelay)
        case .clients:
            // The client may sit on a session a terminal just left, which is now the user's latest,
            // or one tmux closes once unattached: list now so it moves.
            scheduleList(after: .zero)
        case .subscription, .exit, .other:
            break
        }
    }

    /// A pane printed. An agent's screen is read; any other pane may have just started one.
    /// The subscription already waited for its once-a-second check, so its reads do not wait more.
    private func changed(_ key: String, subscribed: Bool) {
        if observations[key] != nil {
            scheduleRead(key, after: subscribed ? .zero : Self.readDelay)
            if subscribed { scheduleFollowUp(key) }
        } else {
            scheduleList(after: listedPanes.contains(key) ? Self.shellPaneDelay : Self.newPaneDelay)
        }
    }

    private func controlEnded(_ socket: String, token: UUID) {
        guard let control = controls[socket], control.token == token else { return }
        controls[socket] = nil
        activity[socket] = nil
        if !control.attached { failed[socket, default: []].insert(control.choice.session) }
        scheduleList(after: Self.listDelay)
    }

    // MARK: Screen reads

    /// Reads one pane's screen after `delay`. A read already waiting covers the output too.
    private func scheduleRead(_ key: String, after delay: Duration = TmuxSource.readDelay) {
        guard reads[key] == nil else { return }
        reads[key] = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            self.reads[key] = nil
            await self.readScreen(key)
        }
    }

    /// One more read a little after a subscription's: the format counts window activity in whole
    /// seconds, so a change later in the same second, with the cursor where it was, shows no new value.
    private func scheduleFollowUp(_ key: String) {
        followUps[key]?.cancel()
        followUps[key] = Task { [weak self] in
            try? await Task.sleep(for: Self.followUpDelay)
            guard !Task.isCancelled, let self else { return }
            self.followUps[key] = nil
            self.scheduleRead(key, after: .zero)
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

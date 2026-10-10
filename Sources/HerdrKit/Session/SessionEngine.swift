import Foundation

/// Keeps a live, correct picture of herdr. Events only mark state dirty; a debounced, serialized
/// `session.snapshot` replaces it. Subscriptions follow the pane set (see `SubscriptionPlanner`),
/// and a broken stream or a missing herdr is reported, never hidden.
public actor SessionEngine {
    public nonisolated let updates: AsyncStream<SessionUpdate>
    private let updatesContinuation: AsyncStream<SessionUpdate>.Continuation

    let client: HerdrClient
    let debounce: Duration
    let subscribeTimeout: Duration
    let now: @Sendable () -> Date

    var planner = SubscriptionPlanner()
    var subscriptions: [Int: EventSubscription] = [:]
    var tracker: TransitionTracker
    var connection = ConnectionState.connecting
    var compatibility = Compatibility.matched
    var session = Session.empty
    var lastPublished: SessionUpdate?
    /// Bumps whenever events may have been missed; a snapshot is continuous only if no bump
    /// happened since the previous one and a subscription was open throughout.
    var epoch = 0
    var lastSnapshotEpoch = -1
    var refreshFailures = 0
    var stopped = false

    private let wake: AsyncStream<Void>.Continuation
    private let wakeStream: AsyncStream<Void>
    var worker: Task<Void, Never>?
    var retryTask: Task<Void, Never>?
    var refreshRetryTask: Task<Void, Never>?
    var dirWatcher: SocketDirWatcher?

    public init(client: HerdrClient = HerdrClient(), debounce: Duration = .milliseconds(100),
                subscribeTimeout: Duration = .seconds(2), seeds: [TransitionTracker.Seed] = [],
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.tracker = TransitionTracker(seeds: seeds)
        self.client = client
        self.debounce = debounce
        self.subscribeTimeout = subscribeTimeout
        self.now = now
        (updates, updatesContinuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(16))
        // Holding at most one wake means events that arrive during a refresh cause exactly one more.
        (wakeStream, wake) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
    }

    public func start() {
        guard worker == nil, !stopped else { return }
        let wakes = wakeStream
        worker = Task { [weak self] in
            for await _ in wakes {
                guard let self else { return }
                await self.refreshAfterDebounce()
            }
        }
        perform(planner.handle(.begin))
    }

    public func stop() {
        stopped = true
        worker?.cancel()
        retryTask?.cancel()
        refreshRetryTask?.cancel()
        dirWatcher?.cancel()
        for subscription in subscriptions.values { subscription.close() }
        subscriptions.removeAll()
        wake.finish()
        updatesContinuation.finish()
    }

    func markDirty() {
        wake.yield()
    }

    private func refreshAfterDebounce() async {
        try? await Task.sleep(for: debounce)
        guard !stopped else { return }
        await refreshOnce()
    }

    /// Reads a snapshot and publishes what changed.
    func refreshOnce() async {
        let subscribedAtStart = planner.active != nil
        let epochAtStart = epoch
        do {
            let snapshot = try await client.snapshot()
            guard !stopped else { return }
            refreshFailures = 0
            compatibility = Compatibility(protocol: snapshot.protocol)
            let continuous = subscribedAtStart && epochAtStart == epoch && lastSnapshotEpoch == epoch
            let transitions = tracker.apply(snapshot, at: now(), continuity: continuous ? .continuous : .afterGap)
            lastSnapshotEpoch = subscribedAtStart && epochAtStart == epoch ? epoch : -1
            session = Session(snapshot: snapshot, tracker: tracker)
            if subscribedAtStart, planner.active != nil { connection = .live }
            publish(transitions)
            // Agent panes only: herdr checks every subscribed pane each 100 ms, and a shell pane
            // that gains an agent announces it with the global `pane.agent_detected`.
            perform(planner.handle(.desired(SubscriptionSet(paneIDs: Set(snapshot.agents.map(\.id))))))
        } catch {
            guard !stopped, planner.active != nil else { return }
            // Subscribed but the read failed: try again shortly rather than show stale state as live.
            refreshFailures += 1
            connection = .stale(SubscriptionPlanner.reason(error as? HerdrError ?? .disconnected))
            publish([])
            let delay = Backoff.delay(afterFailures: refreshFailures)
            refreshRetryTask?.cancel()
            refreshRetryTask = Task { [weak self] in
                try? await Task.sleep(for: delay)
                await self?.markDirty()
            }
        }
    }

    func publish(_ transitions: [Transition]) {
        let update = SessionUpdate(session: session, connection: connection, compatibility: compatibility,
                                   transitions: transitions)
        guard update != lastPublished else { return }
        lastPublished = update
        updatesContinuation.yield(update)
    }
}

import Foundation

/// Decides which event subscription should be open. Pure: the engine feeds it inputs and carries
/// out the commands it returns, so every rule here is unit tested without sockets.
///
/// Rules:
/// - With nothing open, start the global-only set. It names no panes, so it cannot be rejected
///   for a missing one.
/// - To change the pane set, start the new subscription before closing the old one, so there is
///   no window without events.
/// - A rejected upgrade (usually a pane that closed in between) keeps the old subscription and
///   refreshes; the next snapshot gives a corrected set. Repeated failures back off.
/// - When the open subscription ends (`events_lost`, EOF), mark state stale and resubscribe.
struct SubscriptionPlanner: Sendable {
    enum Input: Sendable, Equatable {
        case begin
        case desired(SubscriptionSet)
        case started(generation: Int)
        case startFailed(generation: Int, HerdrError)
        case ended(generation: Int, HerdrError)
        case retry
    }

    enum Command: Sendable, Equatable {
        case start(generation: Int, SubscriptionSet)
        case close(generation: Int)
        /// Read a fresh snapshot.
        case refresh
        /// Events may have been missed: the next snapshot is not continuous with the last.
        case gap
        case scheduleRetry(Duration)
        case state(ConnectionState)
    }

    struct Slot: Sendable, Equatable {
        let generation: Int
        let set: SubscriptionSet
    }

    private(set) var active: Slot?
    private(set) var pending: Slot?
    private(set) var desired = SubscriptionSet.globalOnly
    private(set) var failures = 0
    private(set) var waitingForRetry = false
    private var nextGeneration = 0

    mutating func handle(_ input: Input) -> [Command] {
        switch input {
        case .begin:
            return startIfNeeded()

        case .desired(let set):
            desired = set
            return startIfNeeded()

        case .started(let generation):
            guard let slot = pending, slot.generation == generation else { return [.close(generation: generation)] }
            let previous = active
            active = slot
            pending = nil
            failures = 0
            var commands: [Command] = previous.map { [.close(generation: $0.generation)] } ?? [.gap]
            commands.append(.refresh)
            return commands + startIfNeeded()

        case .startFailed(let generation, let error):
            guard pending?.generation == generation else { return [] }
            pending = nil
            failures += 1
            if active == nil {
                waitingForRetry = true
                return [.state(.disconnected(Self.reason(error))), .scheduleRetry(Backoff.delay(afterFailures: failures))]
            }
            if failures >= 3 {
                waitingForRetry = true
                return [.scheduleRetry(Backoff.delay(afterFailures: failures - 2))]
            }
            return [.refresh]

        case .ended(let generation, let error):
            guard active?.generation == generation else { return [] }
            active = nil
            var commands: [Command] = [.gap, .state(.stale(Self.reason(error)))]
            if pending == nil {
                desired = .globalOnly
                commands += startIfNeeded()
            }
            return commands

        case .retry:
            waitingForRetry = false
            return startIfNeeded()
        }
    }

    private mutating func startIfNeeded() -> [Command] {
        guard pending == nil, !waitingForRetry else { return [] }
        let target: SubscriptionSet
        if let active {
            guard active.set != desired else { return [] }
            target = desired
        } else {
            target = .globalOnly
        }
        let slot = Slot(generation: nextGeneration, set: target)
        nextGeneration += 1
        pending = slot
        return [.start(generation: slot.generation, target)]
    }

    static func reason(_ error: HerdrError) -> String {
        switch error {
        case .notRunning: "herdr is not running"
        case .permissionDenied: "no permission to open the herdr socket"
        case .socketPathTooLong(let path): "herdr socket path is too long: \(path)"
        case .timeout: "herdr did not answer in time"
        case .disconnected: "herdr closed the connection"
        case .lineTooLong: "herdr sent an oversized message"
        case .io(let code): "socket error \(code)"
        case .server(let code, _) where code == .eventsLost: "fell behind herdr's events"
        case .server(let code, let message): "herdr error \(code): \(message)"
        case .unexpectedResponse(let detail): "unexpected reply from herdr: \(detail)"
        }
    }
}

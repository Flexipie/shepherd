import Foundation
@testable import HerdrKit

/// Collects an engine's updates so tests can wait for a state instead of sleeping.
actor UpdateLog {
    private(set) var updates: [SessionUpdate] = []
    private var waiters: [Int: (predicate: @Sendable (SessionUpdate) -> Bool, continuation: CheckedContinuation<SessionUpdate?, Never>)] = [:]
    private var nextID = 0

    static func recording(_ engine: SessionEngine) -> UpdateLog {
        let log = UpdateLog()
        Task { for await update in engine.updates { await log.add(update) } }
        return log
    }

    var latest: SessionUpdate? { updates.last }

    private func add(_ update: SessionUpdate) {
        updates.append(update)
        for (id, waiter) in waiters where waiter.predicate(update) {
            waiters[id] = nil
            waiter.continuation.resume(returning: update)
        }
    }

    /// Waits for the first update (already received or future) matching `predicate`, after
    /// index `after`. Use `count` to wait only for new updates.
    func wait(after index: Int = 0, _ predicate: @escaping @Sendable (SessionUpdate) -> Bool) async throws -> SessionUpdate {
        if let match = updates.dropFirst(index).first(where: predicate) { return match }
        let id = nextID
        nextID += 1
        let result = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                waiters[id] = (predicate, continuation)
            }
        } onCancel: {
            Task { await self.cancel(id) }
        }
        guard let result else { throw TimedOut() }
        return result
    }

    private func cancel(_ id: Int) {
        waiters.removeValue(forKey: id)?.continuation.resume(returning: nil)
    }
}

extension SessionUpdate {
    func status(_ paneID: String) -> AgentStatus? { session.agent(paneID)?.status }
}

import Foundation

/// Awaitable conditions, so tests wait for the fake to reach a state instead of sleeping.
extension FakeHerdrServer {
    public enum Condition: Sendable {
        case subscribers(Int)
        case requests(String, atLeast: Int)
        case snapshots(atLeast: Int)
        case focused(String)
    }

    struct Waiter {
        let condition: Condition
        let continuation: CheckedContinuation<Void, Never>
    }

    /// Returns once `condition` holds. Cancelling the calling task ends the wait.
    public func wait(for condition: Condition) async {
        if isSatisfied(condition) { return }
        let id = nextWaiterID
        nextWaiterID += 1
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if isSatisfied(condition) || Task.isCancelled {
                    continuation.resume()
                } else {
                    waiters[id] = Waiter(condition: condition, continuation: continuation)
                }
            }
        } onCancel: {
            Task { await self.cancelWaiter(id) }
        }
    }

    func resumeWaiters() {
        for (id, waiter) in waiters where isSatisfied(waiter.condition) {
            waiters[id] = nil
            waiter.continuation.resume()
        }
    }

    private func cancelWaiter(_ id: Int) {
        waiters.removeValue(forKey: id)?.continuation.resume()
    }

    private func isSatisfied(_ condition: Condition) -> Bool {
        switch condition {
        case .subscribers(let count): subscriberCount == count
        case .requests(let method, let count): requestCount(method) >= count
        case .snapshots(let count): snapshotCount >= count
        case .focused(let target): focusedTargets.contains(target)
        }
    }
}

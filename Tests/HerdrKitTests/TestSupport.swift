import Foundation
import HerdrFake
import HerdrKit

struct TimedOut: Error {}

/// swift-testing time limits are whole minutes; socket tests want seconds.
func withTimeout<T: Sendable>(_ limit: Duration = .seconds(5), _ operation: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: limit)
            throw TimedOut()
        }
        defer { group.cancelAll() }
        return try await group.next()!
    }
}

func startedFake(_ herd: FakeHerd = .basic) async throws -> FakeHerdrServer {
    let fake = FakeHerdrServer(herd: herd)
    try await fake.start()
    return fake
}

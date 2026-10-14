import Foundation
import ShepherdCore
import Testing
@testable import OpenUsageSource

/// A read-only check against the OpenUsage app on this machine. Skipped unless `SHEPHERD_LIVE=1`.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["SHEPHERD_LIVE"] == "1"))
struct LiveOpenUsageTests {
    @Test func readsEveryEnabledProvider() async throws {
        let report = try await OpenUsageReader().read()
        #expect(!report.providers.isEmpty)
        for provider in report.providers {
            // Names and numbers only; nothing that identifies an account.
            print("\(provider.id.prefix(6)) \(provider.plan ?? "-") stale=\(provider.isStale) "
                + provider.meters.map { "\($0.label) \($0.valueText)" }.joined(separator: ", "))
        }
    }
}

import Foundation
import Testing
@testable import ShepherdCore
@testable import ShepherdModules

@MainActor
final class StubUsageReader: UsageReader {
    var reads = 0
    var expiresIn: TimeInterval = 300
    var error: (any Error)?

    func read() async throws -> UsageReport {
        reads += 1
        if let error { throw error }
        let meter = UsageMeter(id: "session", label: "Session", fraction: 0.4, valueText: "40%")
        return UsageReport(providers: [UsageProvider(id: "claude", name: "Claude", meters: [meter],
                                                     expiresAt: Date().addingTimeInterval(expiresIn))])
    }
}

struct NotRunning: LocalizedError {
    var errorDescription: String? { "OpenUsage is not running." }
}

@MainActor
@Suite struct UsageModuleTests {
    let presence = Presence()
    let reader = StubUsageReader()

    func module(grace: TimeInterval = 0) -> UsageModule {
        let module = UsageModule(context: ModuleContext(store: HerdStore(), presence: presence, actions: RecordingActions(),
                                                        usage: reader))
        module.grace = grace
        return module
    }

    /// Lets observation callbacks and the read task run.
    func settle(_ seconds: Double = 0.05) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    /// Waits up to 3 s for `condition`, so a busy test run does not fail on timing.
    func until(_ condition: () -> Bool) async {
        for _ in 0..<300 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
    }

    @Test func nothingIsReadWhileHidden() async {
        let module = module()
        await settle()
        #expect(reader.reads == 0)
        #expect(module.panel?.emptyText == "Reading usage…")
    }

    @Test func nothingIsReadOnTheAgentsTab() async {
        let module = module()
        presence.setPanel("menu", showing: .agents)
        await settle()
        #expect(reader.reads == 0)
        #expect(module.panel?.tab == .gadgets)
        presence.setPanel("menu", showing: .gadgets)
        await until { reader.reads == 1 }
        #expect(reader.reads == 1)
    }

    @Test func openingReadsOnceUntilItExpires() async {
        let module = module()
        presence.setPanel("notch", showing: .gadgets)
        await until { module.panel?.items.count == 1 }
        #expect(reader.reads == 1)
        #expect(module.panel?.items.count == 1)
        // Closing and opening again within the report's lifetime reads nothing.
        presence.setPanel("notch", showing: nil)
        await settle()
        presence.setPanel("menu", showing: .gadgets)
        await settle()
        #expect(reader.reads == 1)
    }

    @Test func openingAfterItExpiredReadsAgain() async {
        reader.expiresIn = 0.1
        let module = module()
        presence.setPanel("notch", showing: .gadgets)
        await until { module.refreshAt != nil }
        presence.setPanel("notch", showing: nil)
        await settle(0.2)
        #expect(reader.reads == 1)
        presence.setPanel("notch", showing: .gadgets)
        await until { reader.reads == 2 }
        #expect(reader.reads == 2)
        _ = module
    }

    @Test func whileOpenItReadsAgainAtExpiry() async {
        reader.expiresIn = 0.5
        let module = module()
        presence.setPanel("notch", showing: .gadgets)
        await until { module.refreshAt != nil }
        #expect(reader.reads == 1)
        await until { reader.reads == 2 }
        #expect(reader.reads == 2)
        _ = module
    }

    @Test func closingCancelsTheScheduledRead() async {
        reader.expiresIn = 0.2
        let module = module()
        presence.setPanel("notch", showing: .gadgets)
        await until { module.refreshAt != nil }
        presence.setPanel("notch", showing: nil)
        await settle(0.6)
        #expect(reader.reads == 1)
        _ = module
    }

    @Test func aFailedReadIsANotice() async {
        reader.error = NotRunning()
        let module = module()
        presence.setPanel("menu", showing: .gadgets)
        await until { module.panel?.items.isEmpty == false }
        #expect(module.panel?.items == [.notice("OpenUsage is not running.")])
    }

    @Test func noReaderNoSection() {
        let module = UsageModule(context: ModuleContext(store: HerdStore(), presence: presence, actions: RecordingActions()))
        #expect(module.panel == nil)
    }

    @Test func aStaleAccountsPastExpiryDoesNotCount() {
        let now = Date()
        let past = UsageProvider(id: "a", name: "A", isStale: true, meters: [], expiresAt: now.addingTimeInterval(-3600))
        let soon = UsageProvider(id: "b", name: "B", meters: [], expiresAt: now.addingTimeInterval(120))
        #expect(UsageModule.refreshDate(UsageReport(providers: [past, soon]), readAt: now, fallback: 300) == now.addingTimeInterval(120))
        #expect(UsageModule.refreshDate(UsageReport(providers: [past]), readAt: now, fallback: 300) == now.addingTimeInterval(300))
    }
}

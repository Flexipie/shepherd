import Foundation
import ShepherdCore
import Testing
@testable import OpenUsageSource

@Suite struct OpenUsageLimitsTests {
    let report: UsageReport

    init() throws {
        let url = try #require(Bundle.module.url(forResource: "limits", withExtension: "json", subdirectory: "Fixtures"))
        report = try OpenUsageLimits.report(from: Data(contentsOf: url))
    }

    func provider(_ id: String) throws -> UsageProvider {
        try #require(report.providers.first { $0.id == id })
    }

    @Test func claudeAccountsComeFirstAndSameNamesAreToldApart() {
        #expect(report.providers.map(\.id) == ["claude", "claude@a1b2c3", "codex"])
        #expect(report.providers.map(\.name) == ["Claude (Max 5x)", "Claude (Team)", "Codex"])
    }

    @Test func consumptionBecomesMetersInOrder() throws {
        let claude = try provider("claude")
        #expect(claude.meters.map(\.label) == ["Session", "Weekly", "Sonnet"])
        #expect(claude.meters.map(\.valueText) == ["77%", "21%", "3%"])
        #expect(claude.meters[0].fraction == 0.77)
        #expect(claude.meters[0].resetsAt == OpenUsageLimits.date("2030-01-01T14:10:00.000Z"))
        #expect(claude.meters[2].resetsAt == nil)
        #expect(claude.plan == "Max 5x")
        #expect(!claude.isStale)
        #expect(claude.expiresAt == OpenUsageLimits.date("2030-01-01T12:02:00.000Z"))
    }

    @Test func unknownAndBrokenResourcesAreLenient() throws {
        let team = try provider("claude@a1b2c3")
        #expect(team.isStale)
        #expect(team.meters.map(\.label) == ["Weekly", "Extra usage", "Some new limit"])
        #expect(team.meters.map(\.valueText) == ["100%", "$114 of $350", "40 of 200 requests"])
        #expect(team.meters[2].fraction == 0.2)
    }

    @Test func balancesAndErrorsBecomeNotes() throws {
        #expect(try provider("codex").notes == ["2 limit resets available"])
        #expect(try provider("claude@a1b2c3").notes == ["Session expired. Run `claude` to log in again."])
        #expect(report.problems == ["OpenUsage: Not signed in."])
    }

    @Test func labels() {
        #expect(OpenUsageLimits.label("session") == "Session")
        #expect(OpenUsageLimits.label("someNewLimit") == "Some new limit")
        #expect(OpenUsageLimits.label("snake_case_key") == "Snake case key")
        #expect(OpenUsageLimits.dollars(4.5) == "$4.50")
        #expect(OpenUsageLimits.dollars(12) == "$12")
    }

    @Test func somethingElseIsUnreadable() {
        #expect(throws: OpenUsageError.self) { try OpenUsageLimits.report(from: Data("<html>".utf8)) }
    }
}

@MainActor
@Suite struct OpenUsageReaderTests {
    @Test func aClosedPortMeansNotRunning() async throws {
        // Bind and release a port, so nothing listens on it.
        let port = try freePort()
        let reader = OpenUsageReader(baseURL: URL(string: "http://127.0.0.1:\(port)")!)
        await #expect(throws: OpenUsageError.notRunning) { try await reader.read() }
        #expect(OpenUsageError.notRunning.errorDescription?.contains("OpenUsage is not running") == true)
    }

    @Test func onlyLoopbackIsRead() {
        #expect(OpenUsageReader.isLoopback(URL(string: "http://127.0.0.1:6736")!))
        #expect(OpenUsageReader.isLoopback(URL(string: "http://localhost:9000")!))
        #expect(!OpenUsageReader.isLoopback(URL(string: "http://example.com:6736")!))
        #expect(!OpenUsageReader.isLoopback(URL(string: "file:///tmp/x")!))
    }

    private func freePort() throws -> UInt16 {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        defer { close(fd) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        address.sin_port = 0
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        try withUnsafeMutablePointer(to: &address) { pointer in
            try pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { raw in
                guard bind(fd, raw, length) == 0, getsockname(fd, raw, &length) == 0 else { throw POSIXError(.EADDRINUSE) }
            }
        }
        return UInt16(bigEndian: address.sin_port)
    }
}

import Darwin
import Foundation
import Testing
@testable import ShepherdCore

@Suite struct TerminalLocatorTests {
    // 50 herdr client <- 40 zsh <- 30 login <- 20 Ghostty (app) <- 1 launchd
    // 60 herdr server <- 1 launchd
    let parents: [pid_t: pid_t] = [50: 40, 40: 30, 30: 20, 20: 1, 60: 1, 70: 41, 41: 20]

    @Test func findsTheTerminalAndSkipsTheServer() {
        let apps = TerminalLocator.hostingApps(of: [60, 50, 70], parent: { parents[$0] }, isApp: { $0 == 20 })
        #expect(apps == [20])
    }

    @Test func noAppMeansNothing() {
        #expect(TerminalLocator.hostingApps(of: [60], parent: { parents[$0] }, isApp: { _ in false }).isEmpty)
    }

    @Test func survivesParentCycles() {
        #expect(TerminalLocator.hostingApps(of: [5], parent: { $0 == 5 ? 6 : 5 }, isApp: { _ in false }).isEmpty)
    }

    @Test func liveProcessTableIsReadable() {
        #expect(TerminalLocator.parent(of: getpid()) == getppid())
        // Only the user's own processes can be named, which is all herdr needs.
        var buffer = [UInt8](repeating: 0, count: 256)
        let length = proc_name(getpid(), &buffer, UInt32(buffer.count))
        let ownName = String(decoding: buffer.prefix(Int(length)), as: UTF8.self)
        #expect(TerminalLocator.pids(named: ownName).contains(getpid()))
    }

    @Test func elapsedIsHonestAboutPrecision() {
        let now = Date(timeIntervalSince1970: 10_000)
        #expect(Elapsed.short(Since(now.addingTimeInterval(-30), .exact), now: now) == "now")
        #expect(Elapsed.short(Since(now.addingTimeInterval(-300), .exact), now: now) == "5m")
        #expect(Elapsed.short(Since(now.addingTimeInterval(-300), .noLaterThan), now: now) == "5m+")
        #expect(Elapsed.short(Since(now.addingTimeInterval(-3_900), .exact), now: now) == "1h 5m")
        #expect(Elapsed.short(nil) == nil)
        #expect(Elapsed.spoken(Since(now.addingTimeInterval(-30), .exact), now: now) == "just now")
        #expect(Elapsed.spoken(Since(now.addingTimeInterval(-60), .exact), now: now) == "1 minute")
        #expect(Elapsed.spoken(Since(now.addingTimeInterval(-300), .noLaterThan), now: now) == "at least 5 minutes")
        #expect(Elapsed.spoken(Since(now.addingTimeInterval(-3_900), .exact), now: now) == "1 hour 5 minutes")
        #expect(Elapsed.spoken(Since(now.addingTimeInterval(-7_200), .exact), now: now) == "2 hours")
    }
}

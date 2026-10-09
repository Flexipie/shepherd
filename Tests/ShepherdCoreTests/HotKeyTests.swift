import Foundation
import Testing
@testable import ShepherdCore

@Suite struct HotKeyTests {
    @Test func parsesTheDefault() throws {
        let key = try HotKey(parsing: ShepherdConfig.defaultNextHotkey)
        #expect(key.keyCode == 0x2D)
        #expect(key.modifiers == [.control, .option, .command])
    }

    static let spellings: [(String, Int, HotKey.Modifiers)] = [
        ("Ctrl + Opt + J", 0x26, [.control, .option]),
        ("alt+shift+space", 0x31, [.option, .shift]),
        ("command+return", 0x24, [.command]),
        ("f5", 0x60, []),
        ("shift+f12", 0x6F, [.shift]),
        ("control+0", 0x1D, [.control]),
    ]

    @Test func parsesSpellings() throws {
        for (text, code, modifiers) in Self.spellings {
            let key = try HotKey(parsing: text)
            #expect(key.keyCode == UInt32(code), "\(text)")
            #expect(key.modifiers == modifiers, "\(text)")
        }
    }

    @Test(arguments: [("ctrl+option", "cannot parse \"ctrl+option\": no key"),
                      ("ctrl+hyper+n", "cannot parse \"ctrl+hyper+n\": unknown key \"hyper\""),
                      ("ctrl+n+m", "cannot parse \"ctrl+n+m\": more than one key"),
                      ("ctrl+", "cannot parse \"ctrl+\": unknown key \"\""),
                      ("n", "\"n\" needs ctrl, option or cmd"),
                      ("shift+n", "\"shift+n\" needs ctrl, option or cmd")])
    func rejects(text: String, message: String) {
        #expect(throws: ConfigProblem(message)) { try HotKey(parsing: text) }
    }
}

@MainActor
@Suite struct NextInQueueTests {
    let store = HerdStore()
    let presence = Presence()

    init() {
        store.add(StubSource("herdr"))
        store.add(StubSource("other"))
        let base = Date(timeIntervalSince1970: 100)
        store.apply(SourceUpdate(agents: [
            herdAgent("herdr", "a", .blocked, since: base),
            herdAgent("herdr", "b", .blocked, since: base.addingTimeInterval(10), focused: true),
            herdAgent("herdr", "c", .done, since: base),
            herdAgent("herdr", "d", .working),
        ], state: .live), from: "herdr")
        store.apply(SourceUpdate(agents: [herdAgent("other", "x", .blocked, since: base)], state: .stale("behind")), from: "other")
    }

    func next(after last: String?) -> String? {
        NextInQueue.pick(store: store, presence: presence, after: last.map { AgentID(source: "herdr", local: $0) })?.id.local
    }

    @Test func walksTheQueueAndWraps() {
        #expect(next(after: nil) == "a")
        #expect(next(after: "a") == "b")
        #expect(next(after: "b") == "c")
        #expect(next(after: "c") == "a")
        #expect(next(after: "gone") == "a")
    }

    @Test func skipsWhatYouAreLookingAt() {
        presence.frontmostSources = ["herdr"]
        #expect(next(after: "a") == "c")
        #expect(next(after: nil) == "a")
    }

    @Test func nothingWaitingMeansNothing() {
        store.apply(SourceUpdate(agents: [herdAgent("herdr", "d", .working)], state: .live), from: "herdr")
        #expect(next(after: "a") == nil)
    }

    @Test func aLoneAgentStaysTheTarget() {
        store.apply(SourceUpdate(agents: [herdAgent("herdr", "a", .blocked)], state: .live), from: "herdr")
        #expect(next(after: "a") == "a")
    }
}

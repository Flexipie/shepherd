import Foundation
import Testing
@testable import ShepherdCore

@Suite struct ShepherdConfigTests {
    func read(_ json: String) throws -> (config: ShepherdConfig, problems: [String]) {
        try ShepherdConfig.read(Data(json.utf8))
    }

    @Test func emptyObjectIsDefaults() throws {
        let (config, problems) = try read("{}")
        #expect(config == .defaults)
        #expect(config.nextHotkey == "ctrl+option+cmd+n")
        #expect(config.modules == nil)
        #expect(problems.isEmpty)
    }

    @Test func readsEveryKey() throws {
        let (config, problems) = try read(##"""
        {"modules": ["queue", "projects"],
         "tokens": {"projects": [[{"token": "$pr", "fg": "#94e2d5"}, "ticket_state"]], "agents": [["summary"]]},
         "hotkeys": {"next": "ctrl+option+cmd+j"}}
        """##)
        #expect(problems.isEmpty)
        #expect(config.modules == ["queue", "projects"])
        #expect(config.tokens.projects?.first?.map(\.name) == ["pr", "ticket_state"])
        #expect(config.tokens.agents?.first?.map(\.name) == ["summary"])
        #expect(config.nextHotkey == "ctrl+option+cmd+j")
    }

    @Test func nullTurnsTheHotkeyOff() throws {
        #expect(try read(#"{"hotkeys": {"next": null}}"#).config.nextHotkey == nil)
    }

    @Test func badKeysFallBackAndTheRestApplies() throws {
        let (config, problems) = try read(##"""
        {"modules": "queue", "colour": 1,
         "tokens": {"projects": [[{"token": "pr", "fg": "teal"}]], "agents": [["summary"]], "panes": []},
         "hotkeys": {"next": 3, "prev": "x"}}
        """##)
        #expect(config.modules == nil)
        #expect(config.tokens.projects == nil)
        #expect(config.tokens.agents?.first?.map(\.name) == ["summary"])
        #expect(config.nextHotkey == ShepherdConfig.defaultNextHotkey)
        #expect(problems == [
            "config: unknown key \"colour\"",
            "config: modules must be a list of module ids",
            "config: unknown key \"tokens.panes\"",
            "config: tokens.projects[0][0].fg: must be #RGB or #RRGGBB",
            "config: unknown key \"hotkeys.prev\"",
            "config: hotkeys.next must be a string or null, found a number",
        ])
    }

    @Test func unreadableFileThrows() {
        #expect(throws: ConfigProblem.self) { try read("{\"modules\": [") }
        #expect(throws: ConfigProblem("config.json must be an object")) { try read("[]") }
    }

    @Test func pathComesFromTheEnvironment() {
        #expect(ShepherdConfig.defaultURL(environment: ["SHEPHERD_CONFIG_PATH": "/tmp/x/config.json"]).path == "/tmp/x/config.json")
        #expect(ShepherdConfig.defaultURL(environment: [:]).path.hasSuffix("/.config/shepherd/config.json"))
    }
}

@MainActor
@Suite struct ConfigStoreTests {
    struct TimedOut: Error {}

    let directory = FileManager.default.temporaryDirectory.appending(path: "shepherd-config-\(UUID().uuidString)")
    var url: URL { directory.appending(path: "shepherd/config.json") }

    func until(_ condition: () -> Bool) async throws {
        for _ in 0..<300 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw TimedOut()
    }

    /// Writes the way editors do: a temporary file renamed over the original.
    func saveAtomically(_ text: String) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url, options: .atomic)
    }

    /// Writes into the existing file.
    func saveInPlace(_ text: String) throws {
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: Data(text.utf8))
        try handle.close()
    }

    @Test func noFileMeansDefaults() {
        let store = ConfigStore(url: url, watch: false)
        #expect(store.config == .defaults)
        #expect(store.problems.isEmpty)
    }

    @Test func reloadsAfterAtomicSavesAndInPlaceWrites() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        // The directory does not exist yet: the watcher waits for it.
        let store = ConfigStore(url: url)
        defer { store.stop() }
        try await Task.sleep(for: .milliseconds(50))
        try saveAtomically(#"{"modules": ["queue"]}"#)
        try await until { store.config.modules == ["queue"] }

        try saveAtomically(#"{"modules": ["projects", "queue"]}"#)
        try await until { store.config.modules == ["projects", "queue"] }

        try saveInPlace(#"{"modules": ["status"]}"#)
        try await until { store.config.modules == ["status"] }
    }

    @Test func brokenFileKeepsTheLastGoodConfig() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        try saveAtomically(#"{"modules": ["queue"]}"#)
        let store = ConfigStore(url: url)
        defer { store.stop() }
        #expect(store.config.modules == ["queue"])
        try saveAtomically(#"{"modules": ["#)
        try await until { !store.problems.isEmpty }
        #expect(store.config.modules == ["queue"])
        #expect(store.problems.first?.hasPrefix("config.json is not valid JSON") == true)
        #expect(store.problems.first?.hasSuffix("(using the last good config)") == true)

        try saveAtomically(#"{"modules": ["projects"]}"#)
        try await until { store.problems.isEmpty }
        #expect(store.config.modules == ["projects"])

        try FileManager.default.removeItem(at: url)
        try await until { store.config == .defaults }
    }

    @Test func reportedProblemsJoinTheFileOnes() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        try saveAtomically(#"{"colour": 1}"#)
        let store = ConfigStore(url: url, watch: false)
        store.report("hotkeys.next: cannot parse \"x\"", for: "hotkey")
        #expect(store.problems == ["config: unknown key \"colour\"", "hotkeys.next: cannot parse \"x\""])
        store.report(nil, for: "hotkey")
        #expect(store.problems == ["config: unknown key \"colour\""])
    }
}

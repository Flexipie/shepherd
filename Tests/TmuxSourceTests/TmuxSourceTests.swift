import Foundation
import ReportKit
import ReportSource
import ShepherdCore
import Testing
import TmuxKit
import TmuxTestSupport
@testable import TmuxSource

/// The source against a private tmux server running fake agents: scripts named `claude`, so the
/// pane's process tree matches the kind, that print the screens a real agent would show.
@MainActor
@Suite(.enabled(if: TmuxClient.locate() != nil))
struct TmuxSourceTests {
    let binary = TmuxClient.locate() ?? "/usr/bin/false"

    /// Waits up to 6 s for `condition`, so a busy run does not fail on timing.
    func until(_ condition: () -> Bool) async {
        for _ in 0..<600 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
    }

    /// A folder with a `claude` script that prints each screen in turn, a second apart, then waits.
    func fakeClaude(in folder: URL, screens: [String]) throws {
        var script = "#!/bin/sh\n"
        for (index, screen) in screens.enumerated() {
            if index > 0 { script += "sleep 1\n" }
            script += "cat <<'SCREEN'\n\(screen)\nSCREEN\n"
        }
        script += "sleep 120\n"
        let file = folder.appending(path: "claude")
        try script.write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
    }

    static let idle = """
    ────────────────────────────────────
    ❯ Try "write a test"
    ────────────────────────────────────
      ⏵⏵ auto mode on (shift+tab to cycle)
    """

    static let working = """
    ✻ Churning… (5s · esc to interrupt)
    ────────────────────────────────────
    ❯
    ────────────────────────────────────
      ⏵⏵ auto mode on · esc to interrupt
    """

    static let prompt = """
     Do you want to proceed?
     ❯ 1. Yes
       2. No
    """

    /// A scratch folder for the agent's working directory and the tmux socket.
    func scratch() throws -> URL {
        let folder = URL(fileURLWithPath: "/private/tmp").appending(path: "shp-src-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    func running(_ directory: URL, store: HerdStore = HerdStore()) throws -> (HerdStore, TmuxSource) {
        let source = try #require(TmuxSource(binary: binary, directory: directory, activatesTerminal: false))
        store.add(source)
        store.start()
        return (store, source)
    }

    @Test func aPromptInAPaneShowsAsABlockedInferredAgent() async throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        try fakeClaude(in: folder, screens: [Self.prompt])
        // The source starts first and the server after it, so the socket folder's watch must notice it.
        let (store, source) = try running(folder)
        defer { Task { await source.stop() } }
        await until { store.sourceStates[TmuxSource.sourceID] == .live }
        let tmux = try PrivateTmux(binary: binary, folder: folder, command: "\(folder.path)/claude")

        await until { store.needsYou.count == 1 }
        let agent = try #require(store.agents.first)
        #expect(agent.id.source == "tmux")
        #expect(agent.id.local == "tmux:\(tmux.socket):%0")
        #expect(agent.kind == "claude")
        #expect(agent.isInferred)
        #expect(agent.status == .blocked)
        #expect(store.needsYou.map(\.id) == [agent.id])
        #expect(store.projects.map(\.path) == [folder.path])
        #expect(store.capabilities(of: agent.id).contains(.readOutput))
        let text = try await store.read(agent.id, lines: 50)
        #expect(text.contains("Do you want to proceed?"))
    }

    @Test func aTurnThatStartsWorkingIsSeenAfterItSettles() async throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        try fakeClaude(in: folder, screens: [Self.idle, Self.working])
        let tmux = try PrivateTmux(binary: binary, folder: folder, command: "\(folder.path)/claude")
        defer { withExtendedLifetime(tmux) {} }
        let (store, source) = try running(folder)
        defer { Task { await source.stop() } }

        // The working line arrives by output: the control client sees it, the pane is read, and the
        // change waits its two seconds before showing. Whether the idle screen was read first depends
        // on when the listing ran, so only the change is asserted.
        await until { store.agents.first?.status == .working }
        #expect(store.agents.first?.status == .working)
    }

    @Test func aReportFromTheSamePaneReplacesTheScreenRow() async throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        try fakeClaude(in: folder, screens: [Self.prompt])
        let tmux = try PrivateTmux(binary: binary, folder: folder, command: "\(folder.path)/claude")
        let spool = ReportSpool(directory: folder.appending(path: "reports"))
        try spool.write(ReportFile(agent: "tmux:\(tmux.socket):%0", status: .working, kind: "claude", cwd: folder.path,
                                   updatedAt: Date()))
        let store = HerdStore()
        store.add(ReportSource(spool: spool, debounce: .milliseconds(10)))
        let (_, source) = try running(folder, store: store)
        defer { Task { await source.stop() } }

        await until { store.agents.first { !$0.isInferred } != nil && store.sourceStates[TmuxSource.sourceID] == .live }
        try await Task.sleep(for: .milliseconds(300))
        #expect(store.agents.count == 1)
        #expect(store.agents.first?.id.source == "report")
        #expect(store.agents.first?.status == .working)
        #expect(store.projects.allSatisfy { !$0.isInferred })
    }

    @Test func focusingAnAgentSelectsItsPane() async throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        try fakeClaude(in: folder, screens: [Self.idle])
        let tmux = try PrivateTmux(binary: binary, folder: folder, command: "\(folder.path)/claude")
        defer { withExtendedLifetime(tmux) {} }
        let (store, source) = try running(folder)
        defer { Task { await source.stop() } }
        await until { store.agents.count == 1 }
        let agent = try #require(store.agents.first)
        try await store.focus(agent.id)
    }

    @Test func aPromptToABusyAgentIsRefused() async throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        try fakeClaude(in: folder, screens: [Self.working])
        let tmux = try PrivateTmux(binary: binary, folder: folder, command: "\(folder.path)/claude")
        defer { withExtendedLifetime(tmux) {} }
        let (store, source) = try running(folder)
        defer { Task { await source.stop() } }
        await until { store.agents.count == 1 }
        let agent = try #require(store.agents.first)
        await #expect(throws: AgentSourceError.failed("the agent is not idle")) {
            try await store.prompt(agent.id, "hello")
        }
    }
}

import Foundation
import Testing
import TmuxKit
import TmuxTestSupport
@testable import TmuxKit

@Suite(.enabled(if: TmuxClient.locate() != nil))
struct PrivateTmuxTests {
    let binary = TmuxClient.locate() ?? "/usr/bin/false"

    @Test func aServerListsItsPanesWithTheirProcesses() throws {
        let tmux = try PrivateTmux(binary: binary)
        let panes = try tmux.client.panes()
        let pane = try #require(panes.first)
        #expect(panes.count == 1)
        #expect(pane.session == "w")
        #expect(pane.paneID == "%0")
        #expect(pane.isActive)
        #expect(pane.pid > 0)
        #expect(pane.path == tmux.folder.path)
        #expect(pane.socket == tmux.socket)
    }

    @Test func textSentToAPaneAppearsOnItsScreen() throws {
        let tmux = try PrivateTmux(binary: binary)
        try tmux.client.sendLiteral("%0", "-n hello ; $x")
        try tmux.client.sendKeys("%0", ["enter"])
        #expect(tmux.until { (try? tmux.client.screen("%0"))?.contains("-n hello ; $x") == true })
    }

    @Test func aKeyNameIsPressedInThePane() throws {
        let tmux = try PrivateTmux(binary: binary, command: "sh -c 'read x; echo got:$x; sleep 60'")
        try tmux.client.sendLiteral("%0", "yes")
        try tmux.client.sendKeys("%0", ["enter"])
        #expect(tmux.until { (try? tmux.client.screen("%0"))?.contains("got:yes") == true })
    }

    @Test func historyReadsBeyondTheVisibleScreen() throws {
        let tmux = try PrivateTmux(binary: binary, command: "sh -c 'for i in $(seq 1 80); do echo line$i; done; sleep 60'")
        #expect(tmux.until { (try? tmux.client.screen("%0"))?.contains("line80") == true })
        let history = try tmux.client.history("%0", lines: 200)
        #expect(history.contains("line1\n"))
    }

    @Test func aPaneCanBeFocused() throws {
        let tmux = try PrivateTmux(binary: binary)
        try tmux.client.selectWindow("@0")
        try tmux.client.selectPane("%0")
    }

    @Test func aStaleSocketSaysNoServer() throws {
        let tmux = try PrivateTmux(binary: binary)
        let stale = TmuxClient(binary: binary, socket: tmux.folder.appending(path: "none").path)
        #expect(throws: TmuxError.noServer) { try stale.panes() }
    }

    @Test func theServersSocketIsListedInItsFolder() throws {
        let tmux = try PrivateTmux(binary: binary)
        #expect(TmuxSockets.sockets(in: tmux.folder) == [tmux.socket])
    }

    @Test func controlModeReportsOutputOfAPane() async throws {
        let tmux = try PrivateTmux(binary: binary)
        let (events, continuation) = AsyncStream.makeStream(of: ControlEvent.self)
        let control = ControlClient(binary: binary, socket: tmux.socket)
        try await control.start(events: { continuation.yield($0) }, ended: { continuation.finish() })
        // Output is only sent once the control client has attached; poke the pane until it shows.
        let timeout = Task { try? await Task.sleep(for: .seconds(5)); continuation.finish() }
        Task.detached {
            for _ in 0..<50 {
                try? tmux.client.sendLiteral("%0", "tick")
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        var sawOutput = false
        for await event in events {
            if case .output(let pane) = event, pane == "%0" {
                sawOutput = true
                break
            }
        }
        timeout.cancel()
        await control.stop()
        #expect(sawOutput)
    }

    @Test func aControlClientIsNotAListedTerminal() async throws {
        let tmux = try PrivateTmux(binary: binary)
        let control = ControlClient(binary: binary, socket: tmux.socket)
        try await control.start(events: { _ in }, ended: {})
        // Attached after a moment, so the listing sees it.
        try await Task.sleep(for: .milliseconds(300))
        let clients = try tmux.client.clients()
        await control.stop()
        #expect(clients.contains { $0.isControl })
        #expect(clients.allSatisfy { $0.isControl })
    }
}

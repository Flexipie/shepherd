import Foundation
import ShepherdCore
import TmuxKit

/// What one pass over the machine's tmux servers found: each live server's clients, and each pane
/// whose process tree runs a known agent, with the state its screen shows. Built off the main actor.
struct TmuxScan: Sendable {
    struct Server: Sendable {
        let socket: String
        let clients: [TmuxAttachedClient]
    }

    struct Agent: Sendable {
        let pane: TmuxPane
        let kind: String
        let status: HerdStatus
    }

    var servers: [Server] = []
    var agents: [Agent] = []

    /// Lists every socket's panes. The process table is read only when some pane exists, so a machine
    /// with no tmux server runs no process at all.
    static func run(binary: String, directory: URL) -> TmuxScan {
        var scan = TmuxScan()
        var panes: [(TmuxClient, TmuxPane)] = []
        for socket in TmuxSockets.sockets(in: directory) {
            let client = TmuxClient(binary: binary, socket: socket)
            // A socket nothing answers on is stale: it is skipped, not a failure.
            guard let found = try? client.panes() else { continue }
            scan.servers.append(Server(socket: socket, clients: (try? client.clients()) ?? []))
            panes += found.map { (client, $0) }
        }
        guard !panes.isEmpty else { return scan }
        let table = ProcessTable.snapshot()
        for (client, pane) in panes {
            guard let kind = table.names(under: pane.pid).first(where: { ScreenStatus.kinds.contains($0) }),
                  let screen = try? client.screen(pane.paneID) else { continue }
            scan.agents.append(Agent(pane: pane, kind: kind, status: ScreenStatus.status(kind: kind, screen: screen)))
        }
        return scan
    }
}

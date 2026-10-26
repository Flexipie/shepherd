import Foundation
import ShepherdCore
import Testing
import TmuxKit
@testable import TmuxSource

/// Read-only checks against the tmux servers on this machine, with the agents running in them. Skipped
/// unless `SHEPHERD_LIVE=1`. It prints each agent's kind and state, and nothing from the screens or paths.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["SHEPHERD_LIVE"] == "1" && TmuxClient.locate() != nil))
struct LiveTmuxTests {
    @Test func agentsOnThisMachineAreReadAsAStatus() throws {
        let binary = try #require(TmuxClient.locate())
        let scan = TmuxScan.run(binary: binary, directory: TmuxSockets.directory())
        print("tmux servers: \(scan.servers.count), agent panes: \(scan.agents.count)")
        for agent in scan.agents {
            print("agent kind=\(agent.kind) status=\(agent.status) active=\(agent.pane.isActive)")
        }
        #expect(scan.agents.allSatisfy { ScreenStatus.kinds.contains($0.kind) })
    }
}

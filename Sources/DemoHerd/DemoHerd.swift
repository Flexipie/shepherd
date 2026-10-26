import Foundation
import HerdrFake
import HerdrSource
import ReportKit
import ReportSource
import ShepherdCore

/// Demo mode's made-up herd, one part per shipped source: a fake herdr on its own socket served by
/// the real herdr source, Claude Code reports in a spool of its own read by the real report source,
/// and agents read from screens in place of tmux. It never touches the user's herdr, tmux, spool,
/// config or transition log; its socket and spool are temporary and removed on `removeFiles()`.
@MainActor
public final class DemoHerd {
    public let sources: [any AgentSource]
    private let server: FakeHerdrServer
    private let spool: URL

    private init(server: FakeHerdrServer, spool: URL) {
        self.server = server
        self.spool = spool
        sources = [HerdrSource(socketPath: server.path), ReportSource(spool: ReportSpool(directory: spool)), DemoScreenSource()]
    }

    /// Starts the fake herdr and writes the reports. The sources start with the store.
    public static func start() async throws -> DemoHerd {
        let server = FakeHerdrServer(herd: .demo)
        try await server.start()
        let folder = FileManager.default.temporaryDirectory.appending(path: "shepherd-demo-\(UUID().uuidString.prefix(8))")
        let spool = ReportSpool(directory: folder)
        let now = Date.now
        try spool.write(ReportFile(agent: "release-notes", status: .working, message: "Drafting the release notes from merged PRs",
                                   kind: "claude", cwd: "/tmp/site", updatedAt: now))
        try spool.write(ReportFile(agent: "migration", status: .blocked,
                                   question: "Run the database migration now, or wait for review?",
                                   kind: "claude", cwd: "/tmp/billing", updatedAt: now))
        return DemoHerd(server: server, spool: folder)
    }

    /// Removes the socket and the spool, for when the app quits. Safe to call from termination.
    public func removeFiles() {
        try? FileManager.default.removeItem(atPath: server.path)
        try? FileManager.default.removeItem(at: spool)
    }
}

import Dispatch
import Foundation
import ReportKit
import ShepherdCore

/// Agent reports as a Shepherd source: `shepherd report` writes files to the spool, and this turns
/// them into agents. It watches the spool folder rather than polling it. The only timer is one
/// sleep until the next report goes quiet or expires, and none runs while the spool is idle.
@MainActor
public final class ReportSource: AgentSource {
    public static let sourceID = ReportTracker.source

    public let id = ReportSource.sourceID
    public let displayName = "Agent reports"
    /// A report says nothing about a terminal, so there is nothing to focus or read.
    public let capabilities: SourceCapabilities = []
    public let updates: AsyncStream<SourceUpdate>

    private let continuation: AsyncStream<SourceUpdate>.Continuation
    private let spool: ReportSpool
    private let debounce: DispatchTimeInterval
    private var watcher: ReportWatcher?
    private var deadline: Task<Void, Never>?
    private var tracker = ReportTracker()
    /// Reads are numbered as they start. A read that finishes after a newer one is dropped, so an
    /// older listing never overwrites a newer one.
    private var lastRequested = 0
    private var lastApplied = 0

    public init(spool: ReportSpool = ReportSpool(directory: ReportSpool.directory(environment: ProcessInfo.processInfo.environment)),
                debounce: DispatchTimeInterval = .milliseconds(50)) {
        self.spool = spool
        self.debounce = debounce
        (updates, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(16))
    }

    public func start() {
        guard watcher == nil else { return }
        let watcher = ReportWatcher(directory: spool.directory, debounce: debounce) { [weak self] in
            Task { @MainActor in self?.reload() }
        }
        self.watcher = watcher
        watcher.start()
        reload()
    }

    public func stop() async {
        watcher?.stop()
        watcher = nil
        deadline?.cancel()
        deadline = nil
        continuation.finish()
    }

    /// A report has no terminal to focus. The store never asks: `capabilities` is empty.
    public func focus(_ agent: AgentID) async throws {
        throw AgentSourceError.unsupported(.focus)
    }

    /// Reports have no process to host them, so nothing to tell the user is looking at them.
    public func hostApplicationPIDs() -> [pid_t] { [] }

    // MARK: Reading

    /// Reads the spool off the main actor, then applies the result here.
    private func reload() {
        lastRequested += 1
        let generation = lastRequested
        let spool = spool
        Task {
            let result = await Task.detached(priority: .utility) { Result { try spool.read() } }.value
            apply(result, generation: generation)
        }
    }

    private func apply(_ result: Result<ReportSpool.Contents, any Error>, generation: Int) {
        guard generation > lastApplied else { return }
        lastApplied = generation
        let now = Date()
        switch result {
        case .failure(let error):
            // Agents are not shown from a spool that cannot be read. The tracker keeps its state, so
            // when the folder comes back nothing is reported as new.
            continuation.yield(SourceUpdate(
                agents: [], state: .disconnected("agent reports cannot be read: \(error.localizedDescription)"),
                statusLines: ["reports in \(spool.directory.path)"]))
        case .success(let contents):
            let outcome = tracker.apply(contents.reports, at: now)
            if !outcome.expired.isEmpty { removeFiles(for: outcome.expired) }
            let problems = contents.problems.map { "skipped \($0)" }
            continuation.yield(SourceUpdate(
                agents: outcome.agents, projects: outcome.projects, state: .live,
                statusLines: ["reports in \(spool.directory.path)"] + problems, transitions: outcome.transitions))
            scheduleDeadline(outcome.nextDeadline, now: now)
        }
    }

    private func removeFiles(for keys: [String]) {
        let spool = spool
        Task.detached(priority: .utility) {
            for key in keys { try? spool.remove(agent: key) }
        }
    }

    /// One sleep until the given time, then a read. Replaces any earlier one.
    private func scheduleDeadline(_ date: Date?, now: Date) {
        deadline?.cancel()
        deadline = nil
        guard let date else { return }
        let delay = max(0, date.timeIntervalSince(now))
        deadline = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.reload()
        }
    }
}

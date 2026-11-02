import Foundation
import Observation

/// Reads one agent's last visible lines for a surface showing them: once, `debounce` after the
/// agent is shown, then again only when its status changes (including appearing, for a new
/// task's agent). Showing another agent or nothing drops what was read and any read on its way,
/// so nothing is read for an agent no longer shown. The notch stage and the palette's prompt page
/// read at once; the palette's preview waits, so arrowing through the list reads only where the
/// highlight stops.
@MainActor
@Observable
public final class AgentScreenReader {
    /// The agent shown, if any.
    public private(set) var agent: AgentID?
    /// What the last read returned; nil before it arrives.
    public private(set) var text: String?
    /// Why the last read failed, in words.
    public private(set) var error: String?

    @ObservationIgnored private let store: HerdStore
    @ObservationIgnored private let actions: any AgentActions
    @ObservationIgnored private let lineCount: Int
    @ObservationIgnored private let debounce: Duration
    /// Bumps on every change of agent, so late reads and watches for an earlier one are dropped.
    @ObservationIgnored private var generation = 0
    /// Bumps on every read, so an older read finishing after a newer one is dropped.
    @ObservationIgnored private var latestRead = 0
    @ObservationIgnored private var watchedStatus: HerdStatus?

    public init(store: HerdStore, actions: any AgentActions, lineCount: Int, debounce: Duration = .zero) {
        self.store = store
        self.actions = actions
        self.lineCount = lineCount
        self.debounce = debounce
    }

    /// Whether the agent's source can show its lines; when not, nothing is read for it.
    public func canRead(_ agent: AgentID) -> Bool {
        actions.capabilities(of: agent).contains(.readOutput)
    }

    /// Its lines without trailing blank ones, so a box ends at the agent's last words.
    public var lines: [String]? { text.map(Self.lines) }

    public func show(_ agent: AgentID?) {
        guard agent != self.agent else { return }
        generation += 1
        self.agent = agent
        text = nil
        error = nil
        watchedStatus = nil
        guard let agent, canRead(agent) else { return }
        let generation = generation
        Task { [debounce] in
            try? await Task.sleep(for: debounce)
            guard generation == self.generation else { return }
            self.watch(agent, generation)
            self.read(agent, generation)
        }
    }

    public func close() {
        show(nil)
    }

    private func read(_ agent: AgentID, _ generation: Int) {
        latestRead += 1
        let number = latestRead
        Task {
            do {
                let text = try await actions.read(agent, lines: lineCount)
                guard generation == self.generation, number == latestRead else { return }
                self.text = text
                error = nil
            } catch {
                guard generation == self.generation, number == latestRead else { return }
                self.error = "Could not read: \(error)"
            }
        }
    }

    /// Re-reads when the agent's status changes. Re-armed after every change to the store's
    /// agents, for as long as this agent is shown.
    private func watch(_ agent: AgentID, _ generation: Int) {
        watchedStatus = withObservationTracking {
            store.agents.first { $0.id == agent }?.status
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, generation == self.generation else { return }
                let previous = self.watchedStatus
                self.watch(agent, generation)
                if self.watchedStatus != previous, self.watchedStatus != nil { self.read(agent, generation) }
            }
        }
    }

    static func lines(_ text: String) -> [String] {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeLast() }
        return lines
    }
}

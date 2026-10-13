import Observation
import ShepherdCore
import ShepherdUI

/// The agent open in the notch bar's stage, and what was last read from it. It reads the agent's
/// lines once when the stage opens and again only when the agent's status changes while it is
/// open; closed, it reads and watches nothing.
@MainActor
@Observable
final class AgentStageModel {
    private(set) var agent: AgentID?
    private(set) var text: String?
    private(set) var error: String?
    private(set) var isSending = false

    @ObservationIgnored private let store: HerdStore
    @ObservationIgnored private let actions: any AgentActions
    /// Bumps on every open and close, so late reads and watches for an earlier stage are dropped.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var watchedStatus: HerdStatus?

    /// Enough for a whole approval prompt and what led to it.
    static let lineCount = 40

    init(store: HerdStore, actions: any AgentActions) {
        self.store = store
        self.actions = actions
    }

    /// Whether the agent's source can show it here; when not, choosing it jumps instead.
    func canOpen(_ agent: AgentID) -> Bool {
        actions.capabilities(of: agent).contains(.readOutput)
    }

    func open(_ agent: AgentID) {
        guard agent != self.agent else { return }
        generation += 1
        self.agent = agent
        text = nil
        error = nil
        isSending = false
        watch(agent, generation)
        read(agent, generation)
    }

    func close() {
        generation += 1
        agent = nil
        text = nil
        error = nil
        isSending = false
        watchedStatus = nil
    }

    func send(_ action: StageAction) {
        guard let agent, !isSending else { return }
        let generation = generation
        isSending = true
        error = nil
        Task {
            do {
                switch action {
                case .keys(let keys): try await actions.sendKeys(agent, keys)
                case .reply(let text): try await actions.sendText(agent, text)
                case .open, .close: break
                }
            } catch {
                guard generation == self.generation else { return }
                self.error = "Could not send: \(error)"
            }
            if generation == self.generation { isSending = false }
        }
    }

    /// The stage as the bar shows it, with the agent's row from `content` when it has one. nil
    /// when nothing is open or the agent is gone.
    func stage(in content: PanelContent) -> AgentStage? {
        guard let agent, let herdAgent = store.agents.first(where: { $0.id == agent }) else { return nil }
        let row = Self.row(for: agent, in: content) ?? PanelAgentRow(agent: herdAgent, action: .jump(agent))
        let capabilities = actions.capabilities(of: agent)
        let blocked = herdAgent.status == .blocked
        return AgentStage(
            row: row, lines: text.map(Self.lines), choices: blocked ? ChoiceParser.choices(in: text ?? "") : [],
            canSendKeys: blocked && capabilities.contains(.sendKeys), canReply: blocked && capabilities.contains(.sendText),
            error: error, isSending: isSending)
    }

    // MARK: Reading

    private func read(_ agent: AgentID, _ generation: Int) {
        Task {
            do {
                let text = try await actions.read(agent, lines: Self.lineCount)
                guard generation == self.generation else { return }
                self.text = text
            } catch {
                guard generation == self.generation else { return }
                self.error = "Could not read: \(error)"
            }
        }
    }

    /// Re-reads when the agent's status changes. Re-armed after every change to the store's
    /// agents, for as long as this stage is open.
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

    // MARK: Helpers

    /// The lines without trailing blank ones, so the box ends at the agent's last words.
    static func lines(_ text: String) -> [String] {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeLast() }
        return lines
    }

    static func row(for agent: AgentID, in content: PanelContent) -> PanelAgentRow? {
        for section in content.sections {
            for item in section.items {
                switch item {
                case .agent(let row) where row.agent.id == agent: return row
                case .project(let card):
                    if let row = card.agents.first(where: { $0.agent.id == agent }) { return row }
                default: continue
                }
            }
        }
        return nil
    }
}

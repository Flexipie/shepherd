import Observation
import ShepherdCore
import ShepherdUI

/// What the notch bar's stage shows: an agent, or the new task form. For an agent it reads the
/// last lines once when the stage opens and again only when the agent's status changes while it
/// is open; closed, it reads and watches nothing.
@MainActor
@Observable
final class StageModel {
    enum Mode: Equatable {
        case agent(AgentID)
        case newTask
    }

    private(set) var mode: Mode?
    private(set) var text: String?
    private(set) var error: String?
    /// A send or a task start is on its way.
    private(set) var isBusy = false
    /// A task's agent that started but is not in the herd yet: its kind and where it runs.
    private(set) var starting: (kind: String, place: String)?
    /// The project the new task form opened with, when one was asked for.
    private(set) var taskProject: ProjectID?

    @ObservationIgnored private let store: HerdStore
    @ObservationIgnored private let actions: any AgentActions
    @ObservationIgnored private let config: ConfigStore
    /// Bumps on every open and close, so late reads and watches for an earlier stage are dropped.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var watchedStatus: HerdStatus?

    /// Enough for a whole approval prompt and what led to it.
    static let lineCount = 40
    /// Offered first in the new task form, after any kinds the config sets up.
    static let defaultKinds = ["claude", "codex"]

    init(store: HerdStore, actions: any AgentActions, config: ConfigStore) {
        self.store = store
        self.actions = actions
        self.config = config
    }

    /// Whether the agent's source can show it here; when not, choosing it jumps instead.
    func canOpen(_ agent: AgentID) -> Bool {
        actions.capabilities(of: agent).contains(.readOutput)
    }

    /// Projects a new task can start in; none hides the "+".
    var taskProjects: [HerdProject] {
        store.projects.filter { store.canStartTask(in: $0.id) }
    }

    func open(_ agent: AgentID) {
        guard mode != .agent(agent) else { return }
        reset(to: .agent(agent))
        watch(agent, generation)
        read(agent, generation)
    }

    func openNewTask(in project: ProjectID? = nil) {
        guard mode != .newTask || taskProject != project else { return }
        reset(to: .newTask)
        taskProject = project
    }

    func close() {
        reset(to: nil)
    }

    private func reset(to mode: Mode?) {
        generation += 1
        self.mode = mode
        text = nil
        error = nil
        isBusy = false
        starting = nil
        taskProject = nil
        watchedStatus = nil
    }

    // MARK: Sending

    /// Keys go to the agent as they are; text is a reply while it is blocked and a prompt
    /// otherwise. `onSuccess` runs once it was sent, if this stage is still open.
    func send(_ action: StageAction, onSuccess: (@MainActor () -> Void)? = nil) {
        guard case .agent(let agent) = mode, !isBusy else { return }
        let blocked = store.agents.first { $0.id == agent }?.status == .blocked
        run(failure: "Could not send", onSuccess: onSuccess) { [actions] in
            switch action {
            case .keys(let keys): try await actions.sendKeys(agent, keys)
            case .reply(let text) where blocked: try await actions.sendText(agent, text)
            case .reply(let text): try await actions.prompt(agent, text)
            default: break
            }
        }
    }

    /// Starts the task, then shows its agent's stage.
    func start(_ task: NewTask) {
        guard mode == .newTask, !isBusy else { return }
        let generation = generation
        run(failure: "Could not start the task") { [weak self, actions] in
            let agent = try await actions.startTask(task)
            guard let self, generation == self.generation else { return }
            self.open(agent)
            self.starting = (task.kind, task.branch ?? "a new worktree")
        }
    }

    private func run(failure: String, onSuccess: (@MainActor () -> Void)? = nil,
                     _ work: @escaping @MainActor () async throws -> Void) {
        let generation = generation
        isBusy = true
        error = nil
        Task {
            do {
                try await work()
                if generation == self.generation { onSuccess?() }
            } catch {
                guard generation == self.generation else { return }
                self.error = "\(failure): \(error)"
            }
            if generation == self.generation { isBusy = false }
        }
    }

    // MARK: What the bar shows

    func stage(in content: PanelContent) -> BarStage? {
        stage { Self.row(for: $0, in: content) }
    }

    /// The stage, taking an agent's row (with its tokens and context size) from `row`.
    func stage(row: (AgentID) -> PanelAgentRow?) -> BarStage? {
        switch mode {
        case nil: return nil
        case .newTask:
            let projects = taskProjects
            let kinds = (config.config.agents.keys.sorted() + Self.defaultKinds + store.agents.compactMap(\.kind))
                .reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
            let suggested = taskProject ?? projects.first { $0.isFocusedInSource }?.id
            return .newTask(NewTaskStage(projects: projects, suggestedProject: suggested,
                                         kinds: kinds, isStarting: isBusy, error: error))
        case .agent(let agent):
            return agentStage(agent, row: row).map(BarStage.agent)
        }
    }

    /// nil when the agent is gone, unless it is a new task's agent the herd has not shown yet.
    private func agentStage(_ agent: AgentID, row: (AgentID) -> PanelAgentRow?) -> AgentStage? {
        let herdAgent = store.agents.first { $0.id == agent } ?? starting.map {
            HerdAgent(id: agent, kind: $0.kind, name: $0.kind, project: $0.place, status: .unknown, statusLabel: "starting")
        }
        guard let herdAgent else { return nil }
        let row = row(agent) ?? PanelAgentRow(agent: herdAgent, action: .jump(agent))
        let capabilities = actions.capabilities(of: agent)
        let blocked = herdAgent.status == .blocked
        return AgentStage(
            row: row, lines: text.map(Self.lines), choices: blocked ? ChoiceParser.choices(in: text ?? "") : [],
            canSendKeys: blocked && capabilities.contains(.sendKeys),
            canReply: capabilities.contains(blocked ? .sendText : .prompt), prompts: !blocked,
            error: error, isSending: isBusy)
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

    /// Re-reads when the agent's status changes (including appearing, for a new task's agent).
    /// Re-armed after every change to the store's agents, for as long as this stage is open.
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

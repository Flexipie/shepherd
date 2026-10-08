import Foundation
import Observation

/// The main-actor face of `SessionEngine`. Each property changes only when its value does, so a
/// view that reads only `needsYou` is not redrawn by unrelated updates.
@MainActor
@Observable
public final class SessionStore {
    public private(set) var session = Session.empty
    public private(set) var needsYou: [AgentState] = []
    public private(set) var workingCount = 0
    public private(set) var connection = ConnectionState.connecting
    public private(set) var compatibility = Compatibility.matched
    /// The transitions behind the most recent update.
    public private(set) var lastTransitions: [Transition] = []

    @ObservationIgnored public let client: HerdrClient
    @ObservationIgnored private let engine: SessionEngine
    @ObservationIgnored private var task: Task<Void, Never>?

    public init(client: HerdrClient = HerdrClient(), debounce: Duration = .milliseconds(100)) {
        self.client = client
        self.engine = SessionEngine(client: client, debounce: debounce)
    }

    public func start() {
        guard task == nil else { return }
        let engine = engine
        task = Task { [weak self] in
            await engine.start()
            for await update in engine.updates {
                self?.apply(update)
            }
        }
    }

    public func stop() async {
        task?.cancel()
        task = nil
        await engine.stop()
    }

    /// Focuses the agent's pane in herdr, which marks a finished agent as seen.
    public func focus(paneID: String) async throws {
        try await client.focusAgent(paneID: paneID)
    }

    package func apply(_ update: SessionUpdate) {
        if session != update.session { session = update.session }
        if needsYou != update.session.needsYou { needsYou = update.session.needsYou }
        if workingCount != update.session.workingCount { workingCount = update.session.workingCount }
        if connection != update.connection { connection = update.connection }
        if compatibility != update.compatibility { compatibility = update.compatibility }
        if !update.transitions.isEmpty { lastTransitions = update.transitions }
    }
}

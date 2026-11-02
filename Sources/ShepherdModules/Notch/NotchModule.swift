import Foundation
import Observation
import ShepherdCore

/// Decides what the notch pill shows. The pill tells news, not a state: an agent that becomes
/// blocked or finishes shows briefly, then the pill folds back to the paw and only its count
/// remembers it. An agent still blocked after `notch.escalateAfter` shows once more. Screen
/// readings never raise it, and nothing shows for the agent the user is already looking at, or
/// from a source that is not live.
@MainActor
@Observable
public final class NotchModule: ShepherdModule {
    public static let id = "notch"
    public static var briefDuration: Duration = .seconds(4)

    @ObservationIgnored private let context: ModuleContext
    /// Agents currently inside a brief window.
    private(set) var shown: Set<AgentID> = []
    /// Each agent's windows still to come.
    @ObservationIgnored private var timers: [AgentID: Task<Void, Never>] = [:]

    public init(context: ModuleContext) {
        self.context = context
        watchEvents()
    }

    public var notch: NotchItem? {
        let store = context.store
        let presence = context.presence
        let waiting = store.needsYou.filter { agent in
            store.sourceStates[agent.id.source]?.isLive == true && !presence.isLookingAt(agent)
        }
        guard let agent = waiting.first(where: { shown.contains($0.id) && !$0.isInferred }) else { return nil }
        return NotchItem(agent: agent, reason: agent.status == .blocked ? .blocked : .finished, others: waiting.count - 1)
    }

    /// Reads the store's events, which drop nothing while a batch is handled and leave out screen
    /// readings.
    private func watchEvents() {
        let stream = context.store.events()
        Task { [weak self] in
            for await event in stream {
                guard let self else { return }
                if case .transitions(let transitions) = event { self.handle(transitions) }
            }
        }
    }

    /// Opens a brief window for each change seen happening, not an agent that appeared already
    /// waiting. One-shot timers, no polling.
    func handle(_ transitions: [HerdTransition]) {
        for transition in transitions {
            let agent = transition.agent
            if transition.from == .blocked, transition.to != .blocked {
                timers.removeValue(forKey: agent)?.cancel()
                shown.remove(agent)
            }
            guard transition.from != nil else { continue }
            if transition.to == .done { alert(agent, again: nil) }
            if transition.to == .blocked {
                let seconds = context.config.config.notchEscalateAfter
                alert(agent, again: seconds > 0 ? .seconds(seconds) : nil)
            }
        }
    }

    /// Shows the agent for `briefDuration`, and once more `again` after it started.
    private func alert(_ agent: AgentID, again: Duration?) {
        timers[agent]?.cancel()
        shown.insert(agent)
        timers[agent] = Task { [weak self] in
            // A sleep that ended just before a cancel still returns, so check after each one.
            func wait(_ duration: Duration) async throws {
                try await Task.sleep(for: duration)
                try Task.checkCancellation()
            }
            do {
                try await wait(Self.briefDuration)
                self?.shown.remove(agent)
                guard let again else { return }
                try await wait(max(.zero, again - Self.briefDuration))
                self?.shown.insert(agent)
                try await wait(Self.briefDuration)
                self?.shown.remove(agent)
            } catch {
                // Cancelled: whoever cancelled owns `shown` now.
            }
        }
    }
}

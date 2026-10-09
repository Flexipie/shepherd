import Foundation
import Observation
import ShepherdCore

/// Decides what the notch pill shows. A blocked agent stays until it is no longer blocked. A
/// finished agent shows briefly, then the pill collapses and only the menu bar count remembers
/// it. Nothing shows for the agent the user is already looking at, or from a source that is not
/// live.
@MainActor
@Observable
public final class NotchModule: ShepherdModule {
    public static let id = "notch"
    public static var briefDuration: Duration = .seconds(4)

    @ObservationIgnored private let context: ModuleContext
    /// Finished agents currently inside their brief window.
    private(set) var brief: Set<AgentID> = []

    public init(context: ModuleContext) {
        self.context = context
        watchTransitions()
    }

    public var notch: NotchItem? {
        let store = context.store
        let presence = context.presence
        let waiting = store.needsYou.filter { agent in
            store.sourceStates[agent.id.source]?.isLive == true && !presence.isLookingAt(agent)
        }
        if let blocked = waiting.first(where: { $0.status == .blocked }) {
            return NotchItem(agent: blocked, reason: .blocked, others: waiting.count - 1)
        }
        if let finished = waiting.first(where: { brief.contains($0.id) }) {
            return NotchItem(agent: finished, reason: .finished, others: waiting.count - 1)
        }
        return nil
    }

    /// Starts a brief window for each agent that just finished. One-shot timers, no polling.
    private func watchTransitions() {
        withObservationTracking {
            _ = context.store.lastTransitions
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.startBriefWindows(for: self.context.store.lastTransitions)
                self.watchTransitions()
            }
        }
    }

    func startBriefWindows(for transitions: [HerdTransition]) {
        // Only a change seen happening counts, not an agent that appeared already finished.
        for transition in transitions where transition.from != nil && transition.to == .done {
            let agent = transition.agent
            brief.insert(agent)
            Task { [weak self] in
                try? await Task.sleep(for: Self.briefDuration)
                self?.brief.remove(agent)
            }
        }
    }
}

import Observation
import ShepherdCore

/// Posts a system notification when an agent becomes blocked while the user is not looking at
/// it, and withdraws it once the agent moves on. Only changes seen happening count, from live
/// sources. With `notifications` "auto" it stays quiet for a source that posts its own; "off"
/// posts nothing. It has no contributions: it reacts to transitions and nothing else.
@MainActor
public final class NotificationsModule: ShepherdModule {
    public static let id = "notifications"

    private let context: ModuleContext

    public init(context: ModuleContext) {
        self.context = context
        watchTransitions()
    }

    private func watchTransitions() {
        withObservationTracking {
            _ = context.store.lastTransitions
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.handle(self.context.store.lastTransitions)
                self.watchTransitions()
            }
        }
    }

    func handle(_ transitions: [HerdTransition]) {
        guard let notifier = context.notifier else { return }
        let store = context.store
        for transition in transitions {
            if transition.from == .blocked, transition.to != .blocked {
                notifier.withdraw(transition.agent)
            }
            guard transition.from != nil, transition.to == .blocked, wanted(from: transition.agent.source),
                  let agent = store.agents.first(where: { $0.id == transition.agent }),
                  !context.presence.isLookingAt(agent) else { continue }
            let canReply = store.capabilities(of: agent.id).contains(.sendText)
            notifier.post(AgentNotice(agent: agent, reason: .blocked, canReply: canReply))
        }
    }

    private func wanted(from source: SourceID) -> Bool {
        guard context.store.sourceStates[source]?.isLive == true else { return false }
        switch context.config.config.notifications {
        case .off: return false
        case .on: return true
        case .auto: return !context.store.sourcesPostingAlerts.contains(source)
        }
    }
}

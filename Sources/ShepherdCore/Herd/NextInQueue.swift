/// Which agent the "next" hotkey goes to: the first waiting agent from a live source that the
/// user is not already looking at. Pressing again moves on past the agent it went to last, even
/// before the source reports the focus change, so repeated presses walk the queue.
@MainActor
public enum NextInQueue {
    public static func pick(store: HerdStore, presence: Presence, after last: AgentID?) -> HerdAgent? {
        let candidates = store.needsYou.filter { agent in
            store.sourceStates[agent.id.source]?.isLive == true && !presence.isLookingAt(agent)
        }
        guard let last, let index = candidates.firstIndex(where: { $0.id == last }) else { return candidates.first }
        let rest = candidates[(index + 1)...] + candidates[..<index]
        return rest.first ?? candidates[index]
    }
}

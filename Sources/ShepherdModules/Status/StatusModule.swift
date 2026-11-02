import ShepherdCore

/// The menu bar glyph: a count when agents need you, nothing extra when they do not, and a
/// dimmed glyph whenever the state is not live. Only a blocked agent fills the paw and turns it
/// orange; finished agents are a plain count, so the badge does not stay loud after work ends.
@MainActor
public final class StatusModule: ShepherdModule {
    public static let id = "status"
    private let context: ModuleContext

    public init(context: ModuleContext) {
        self.context = context
    }

    public var status: StatusContribution? {
        let store = context.store
        switch store.overallState {
        case .connecting:
            return StatusContribution(symbol: "pawprint", emphasis: .dimmed, accessibilityLabel: "Shepherd: connecting")
        case .disconnected(let reason), .stale(let reason):
            return StatusContribution(symbol: "pawprint", emphasis: .dimmed, accessibilityLabel: "Shepherd: \(reason)")
        case .live, .absent:
            // Live means every source is live or absent, and an absent source has no agents.
            let waiting = store.needsYou.count
            guard waiting > 0 else {
                return StatusContribution(symbol: "pawprint",
                                          accessibilityLabel: "Shepherd: nothing needs you, \(store.workingCount) working")
            }
            let blocked = store.needsYou.count { $0.status == .blocked }
            let finished = waiting - blocked
            let label = [(blocked, "blocked"), (finished, "finished")].filter { $0.0 > 0 }.map { "\($0.0) \($0.1)" }
            return StatusContribution(symbol: blocked > 0 ? "pawprint.fill" : "pawprint", count: waiting,
                                      emphasis: blocked > 0 ? .attention : .normal,
                                      accessibilityLabel: "Shepherd: " + label.joined(separator: ", "))
        }
    }
}

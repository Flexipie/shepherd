import HerdrKit
import ShepherdCore

/// The menu bar glyph: a count when agents need you, nothing extra when they do not, and a
/// dimmed glyph whenever the state is not live.
@MainActor
public final class StatusModule: ShepherdModule {
    public static let id = "status"
    private let context: ModuleContext

    public init(context: ModuleContext) {
        self.context = context
    }

    public var status: StatusContribution? {
        let store = context.store
        switch store.connection {
        case .connecting:
            return StatusContribution(symbol: "pawprint", emphasis: .dimmed, accessibilityLabel: "Shepherd: connecting to herdr")
        case .disconnected(let reason), .stale(let reason):
            return StatusContribution(symbol: "pawprint", emphasis: .dimmed, accessibilityLabel: "Shepherd: \(reason)")
        case .live:
            let waiting = store.needsYou.count
            guard waiting > 0 else {
                return StatusContribution(symbol: "pawprint",
                                          accessibilityLabel: "Shepherd: nothing needs you, \(store.workingCount) working")
            }
            return StatusContribution(symbol: "pawprint.fill", count: waiting, emphasis: .attention,
                                      accessibilityLabel: "Shepherd: \(waiting) \(waiting == 1 ? "agent needs" : "agents need") you")
        }
    }
}

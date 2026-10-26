import SwiftUI

/// Where a surface's "now" comes from. Views never read the clock themselves, so times tick
/// once a minute while the surface exists and snapshots are stable.
public enum PanelClock: Sendable {
    case live
    case fixed(Date)
}

/// A surface's content at the clock's "now": redrawn every minute when live.
struct Clocked<Content: View>: View {
    let clock: PanelClock
    @ViewBuilder let content: (Date) -> Content

    var body: some View {
        switch clock {
        case .live: TimelineView(.everyMinute) { context in content(context.date) }
        case .fixed(let date): content(date)
        }
    }
}

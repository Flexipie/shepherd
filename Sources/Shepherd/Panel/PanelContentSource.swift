import ShepherdCore
import ShepherdUI

/// What the panel shows, computed from the modules and the store. Shared by the menu bar panel
/// and the notch surface, so the two never drift. Read inside observation tracking to redraw
/// when any of it changes.
@MainActor
struct PanelContentSource {
    let store: HerdStore
    let registry: ModuleRegistry
    let config: ConfigStore

    func current() -> PanelContent {
        PanelContent(sections: registry.modules.compactMap(\.panel), statusLines: HerdSummary.lines(store),
                     problems: config.problems)
    }
}

/// The herd's state in a line, then each source's own lines: shared by the panel footer and the
/// status item's menu.
@MainActor
enum HerdSummary {
    static func lines(_ store: HerdStore) -> [String] {
        var lines: [String]
        switch store.overallState {
        case .connecting: lines = ["Connecting…"]
        case .disconnected(let reason): lines = ["Not connected: \(reason). Retrying."]
        case .stale(let reason): lines = ["Reconnecting: \(reason)"]
        case .live: lines = ["\(store.workingCount) working, \(store.needsYou.count) waiting"]
        }
        for source in store.sources {
            lines += store.statusLines[source.id] ?? []
        }
        return lines
    }
}

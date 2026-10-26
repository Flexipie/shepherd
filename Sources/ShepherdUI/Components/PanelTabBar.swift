import ShepherdCore
import SwiftUI

/// The Agents | Gadgets switch at the top of the panel and the notch bar. Drawn by hand rather
/// than as a segmented picker, which is an AppKit control that snapshots cannot render.
struct PanelTabBar: View {
    let selected: PanelTab
    let onTab: (PanelTab) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(PanelTab.allCases.enumerated()), id: \.element) { index, tab in
                Button {
                    onTab(tab)
                } label: {
                    Text(tab.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(tab == selected ? .primary : .secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(tab == selected ? Color.primary.opacity(0.14) : .clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("\(tab.title) (⌘\(index + 1))")
                .accessibilityAddTraits(tab == selected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Capsule().fill(Color.primary.opacity(0.05)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tabs")
    }
}

extension PanelContent {
    /// Whether the tabs show: only when some section sits on a tab other than Agents.
    public var hasTabs: Bool { sections.contains { $0.tab != .agents } }

    /// The tab actually shown: `tab`, or Agents when there are no tabs.
    public func shownTab(_ tab: PanelTab) -> PanelTab { hasTabs ? tab : .agents }

    /// The sections on the tab shown for `tab`, in module order or as `layout` arranged them.
    public func sections(on tab: PanelTab) -> [PanelSection] {
        let shown = shownTab(tab)
        return sections.filter { $0.tab == shown }
    }
}

extension PanelTab {
    /// The tab for ⌘1, ⌘2 and so on.
    static func forDigit(_ characters: String) -> PanelTab? {
        guard let digit = Int(characters), digit >= 1, digit <= allCases.count else { return nil }
        return allCases[digit - 1]
    }
}

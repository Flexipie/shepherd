import ShepherdCore
import SwiftUI

/// The Agents | Gadgets switch at the top of the notch bar, with a faint ⌘1 and ⌘2 after each
/// title. One pill marks the selected tab and slides between them. Drawn by hand rather than as
/// a segmented picker, which is an AppKit control that snapshots cannot render.
struct PanelTabBar: View {
    let selected: PanelTab
    let onTab: (PanelTab) -> Void

    @Namespace private var pill

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(PanelTab.allCases.enumerated()), id: \.element) { index, tab in
                Button {
                    onTab(tab)
                } label: {
                    HStack(spacing: NotchStyle.small) {
                        Text(tab.title)
                            .font(.system(size: NotchStyle.body, weight: .semibold))
                            .foregroundStyle(tab == selected ? Color.primary : NotchStyle.secondary)
                        KeyHint("⌘\(index + 1)")
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background {
                        if tab == selected {
                            Capsule().fill(NotchStyle.selected).matchedGeometryEffect(id: "pill", in: pill)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("\(tab.title) (⌘\(index + 1))")
                .accessibilityAddTraits(tab == selected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Capsule().fill(NotchStyle.card))
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

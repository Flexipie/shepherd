import AppKit
import ShepherdCore
import SwiftUI

/// A module's section: its title (with a count for the needs-you queue), its empty text, then its
/// items. Shared by the menu bar panel and the notch bar's columns.
struct PanelSectionView: View {
    let section: PanelSection
    let now: Date
    let selection: PanelTarget.ID?
    var jump: ((PanelAction) -> Void)?
    let perform: (PanelAction) -> Void
    let select: (PanelTarget.ID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(section.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)
                if section.id == "queue", !section.items.isEmpty {
                    Text("\(section.items.count)")
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            if section.items.isEmpty {
                Text(section.emptyText)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }
            ForEach(section.items.indices, id: \.self) { index in
                PanelItemView(item: section.items[index], sectionID: section.id, now: now, selection: selection,
                              jump: jump, perform: perform, select: select)
            }
        }
    }
}

/// One item: an agent row (with its project), a project card, a usage card or a notice. Hovering selects.
/// With `jump`, agent rows show a jump arrow and ⌘-click jumps instead of `perform`.
struct PanelItemView: View {
    let item: PanelItem
    let sectionID: String
    let now: Date
    let selection: PanelTarget.ID?
    var jump: ((PanelAction) -> Void)?
    let perform: (PanelAction) -> Void
    let select: (PanelTarget.ID) -> Void

    var body: some View {
        switch item {
        case .agent(let row):
            let id = row.action.map { PanelTarget.id(section: sectionID, action: $0) }
            AgentRow(row: row, now: now, showsProject: true, isSelected: id != nil && id == selection,
                     onJump: jumpAction(row))
                .onTapGesture { if let action = row.action { tap(action, perform: perform, jump: jump) } }
                .onHover { inside in if inside, let id { select(id) } }
                .id(id)
        case .project(let card):
            ProjectCard(card: card, now: now, selection: selection, sectionID: sectionID, jump: jump, perform: perform) { id in
                if let id { select(id) }
            }
        case .usage(let provider):
            UsageCard(provider: provider, now: now)
        case .notice(let text):
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
        }
    }

    private func jumpAction(_ row: PanelAgentRow) -> (() -> Void)? {
        guard let jump, let action = row.action else { return nil }
        return { jump(action) }
    }
}

/// A click on a row: ⌘-click jumps when the row offers it, a plain click performs.
@MainActor
func tap(_ action: PanelAction, perform: (PanelAction) -> Void, jump: ((PanelAction) -> Void)?) {
    if let jump, NSEvent.modifierFlags.contains(.command) {
        jump(action)
    } else {
        perform(action)
    }
}

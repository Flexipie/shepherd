import ShepherdCore
import SwiftUI

/// A module's section: its title (with a count for the needs-you queue), its empty text, then its
/// items. Shared by the menu bar panel and the notch bar's columns.
struct PanelSectionView: View {
    let section: PanelSection
    let now: Date
    let rows: RowContext

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
                PanelItemView(item: section.items[index], now: now, rows: rows)
            }
        }
    }
}

/// One item, drawn the same way on every surface: an agent row (with its project), a project or
/// repo card, a gadget card or a notice. This is the one place an item kind meets its view.
struct PanelItemView: View {
    let item: PanelItem
    let now: Date
    let rows: RowContext

    var body: some View {
        switch item {
        case .agent(let row):
            AgentRow(row: row, now: now, showsProject: true, isSelected: rows.isSelected(row.action),
                     onJump: rows.onJump(row.action))
                .choosable(row.action, in: rows)
        case .project(let card):
            ProjectCard(card: card, now: now, rows: rows)
        case .repo(let card):
            RepoCard(card: card, now: now, rows: rows)
        case .gadget(let card):
            GadgetCardView(card: card, now: now)
        case .notice(let text):
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
        }
    }
}

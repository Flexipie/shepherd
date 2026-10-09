import ShepherdCore
import SwiftUI

/// One project: its name and token lines, then its agents.
struct ProjectCard: View {
    let card: PanelProjectCard
    let now: Date
    let selection: PanelTarget.ID?
    let sectionID: String
    let perform: (PanelAction) -> Void
    let hover: (PanelTarget.ID?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            header
            ForEach(card.agents.indices, id: \.self) { index in
                let row = card.agents[index]
                let id = row.action.map { PanelTarget.id(section: sectionID, action: $0) }
                AgentRow(row: row, now: now, isSelected: id != nil && id == selection)
                    .onTapGesture { if let action = row.action { perform(action) } }
                    .onHover { inside in if let id { hover(inside ? id : nil) } }
            }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.045)))
    }

    private var header: some View {
        let id = card.action.map { PanelTarget.id(section: sectionID, action: $0) }
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(card.project.name.isEmpty ? "Untitled" : card.project.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    if card.project.isFocusedInSource {
                        Circle().fill(Color.accentColor).frame(width: 5, height: 5).accessibilityHidden(true)
                    }
                }
                TokenLines(lines: card.tokens, isLive: card.isLive)
            }
            Spacer(minLength: 8)
            Text(summary)
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .opacity(card.isLive ? 1 : 0.6)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 7).fill(id != nil && id == selection ? Color.accentColor.opacity(0.18) : .clear))
        .contentShape(Rectangle())
        .onTapGesture { if let action = card.action { perform(action) } }
        .onHover { inside in if let id { hover(inside ? id : nil) } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(card.action == nil ? .isHeader : [.isHeader, .isButton])
    }

    /// "2 agents", "1 waiting of 3".
    private var summary: String {
        let count = card.agents.count
        let waiting = card.agents.count { $0.isLive && $0.agent.status.needsYou }
        if count == 0 { return "no agents" }
        if waiting > 0 { return "\(waiting) waiting of \(count)" }
        return count == 1 ? "1 agent" : "\(count) agents"
    }

    private var accessibilityText: String {
        var parts = [card.project.name, summary]
        if card.project.isFocusedInSource { parts.append("focused") }
        if !card.isLive { parts.append("not live") }
        parts += card.tokens.flatMap { $0.map(\.text) }
        return parts.joined(separator: ", ")
    }
}

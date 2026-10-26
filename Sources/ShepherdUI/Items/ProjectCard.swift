import ShepherdCore
import SwiftUI

/// One project: its name and token lines, then its agents.
struct ProjectCard: View {
    let card: PanelProjectCard
    let now: Date
    let rows: RowContext

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ProjectHeader(card: card, rows: rows)
            ProjectAgentRows(card: card, now: now, rows: rows)
        }
        .card()
    }
}

/// A project's agents, each selectable and choosable.
struct ProjectAgentRows: View {
    let card: PanelProjectCard
    let now: Date
    let rows: RowContext

    var body: some View {
        ForEach(card.agents.indices, id: \.self) { index in
            let row = card.agents[index]
            AgentRow(row: row, now: now, isSelected: rows.isSelected(row.action), onJump: rows.onJump(row.action))
                .choosable(row.action, in: rows)
        }
    }
}

/// A project's name (with a dot when its source has it focused), token lines and agent summary.
/// Choosing it focuses the project. `compact` is a checkout's sub-header inside a repo card,
/// with a branch glyph for a linked worktree.
struct ProjectHeader: View {
    let card: PanelProjectCard
    var compact = false
    let rows: RowContext

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    if compact, card.project.repo?.isLinkedCheckout == true {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                    Text(card.project.name.isEmpty ? "Untitled" : card.project.name)
                        .font(.system(size: compact ? 12 : 13, weight: compact ? .medium : .semibold))
                        .lineLimit(1)
                    if card.project.isFocusedInSource {
                        Circle().fill(Color.accentColor).frame(width: 5, height: 5).accessibilityHidden(true)
                    }
                }
                TokenLines(lines: card.tokens, isLive: card.isLive)
            }
            Spacer(minLength: 8)
            Text(ProjectSummary.text(card.agents))
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .opacity(card.isLive ? 1 : 0.6)
        .rowChrome(isSelected: rows.isSelected(card.action), vertical: compact ? 3 : 5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(card.action == nil ? .isHeader : [.isHeader, .isButton])
        .choosable(card.action, in: rows.withoutJump)
    }

    private var accessibilityText: String {
        var parts = [card.project.name, ProjectSummary.text(card.agents)]
        if card.project.repo?.isLinkedCheckout == true { parts.append("worktree") }
        if card.project.isFocusedInSource { parts.append("focused") }
        if !card.isLive { parts.append("not live") }
        parts += card.tokens.flatMap { $0.map(\.text) }
        return parts.joined(separator: ", ")
    }
}

enum ProjectSummary {
    /// "2 agents", "1 waiting of 3".
    static func text(_ agents: [PanelAgentRow]) -> String {
        let count = agents.count
        let waiting = agents.count { $0.isLive && $0.agent.status.needsYou }
        if count == 0 { return "no agents" }
        if waiting > 0 { return "\(waiting) waiting of \(count)" }
        return count == 1 ? "1 agent" : "\(count) agents"
    }
}

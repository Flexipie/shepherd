import ShepherdCore
import SwiftUI

/// The checkouts of one repo in one card: the repo's name, then each checkout as a compact
/// sub-header (its label, focus dot and tokens; choosing it focuses that checkout) with its
/// agents under it. A checkout with one agent is a single row instead: its label, the agent's
/// state, and both their tokens; choosing it jumps to the agent.
struct RepoCard: View {
    let card: PanelRepoCard
    let now: Date
    let rows: RowContext

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            header
            ForEach(card.projects.indices, id: \.self) { index in
                let project = card.projects[index]
                Divider().padding(.horizontal, 8).padding(.vertical, 2)
                if let agent = Self.soleAgent(project) {
                    soleAgentRow(project, agent)
                } else {
                    ProjectHeader(card: project, compact: true, rows: rows)
                    ProjectAgentRows(card: project, now: now, rows: rows)
                }
            }
        }
        .card()
    }

    /// The agent of a checkout that has exactly one, which then shares the checkout's row. The
    /// keyboard targets follow the same rule.
    static func soleAgent(_ project: PanelProjectCard) -> PanelAgentRow? {
        project.agents.count == 1 ? project.agents.first : nil
    }

    private func soleAgentRow(_ project: PanelProjectCard, _ agent: PanelAgentRow) -> some View {
        let merged = PanelAgentRow(agent: agent.agent, tokens: project.tokens + agent.tokens, isLive: agent.isLive,
                                   action: agent.action, contextTokens: agent.contextTokens, finalMessage: agent.finalMessage)
        return AgentRow(row: merged, now: now, checkout: project.project, isSelected: rows.isSelected(agent.action),
                        onJump: rows.onJump(agent.action))
            .choosable(agent.action, in: rows)
    }

    private var header: some View {
        let agents = card.projects.flatMap(\.agents)
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(card.name.isEmpty ? "Untitled" : card.name)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(ProjectSummary.text(agents))
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .opacity(card.projects.contains { $0.isLive } ? 1 : 0.6)
        .padding(.horizontal, 8)
        .padding(.top, 5)
        .padding(.bottom, 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(card.name), \(card.projects.count) checkouts, \(ProjectSummary.text(agents))")
        .accessibilityAddTraits(.isHeader)
    }
}

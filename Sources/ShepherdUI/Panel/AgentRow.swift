import ShepherdCore
import SwiftUI

/// An agent in the queue (with its project) or in a project card (without). One accessibility
/// element: "codex, api, needs you, 4 minutes".
struct AgentRow: View {
    let row: PanelAgentRow
    let now: Date
    var showsProject = false
    var isSelected = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            StateGlyph(status: row.agent.status, isLive: row.isLive, size: showsProject ? 14 : 12)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(row.agent.name)
                        .font(.system(size: showsProject ? 13 : 12, weight: .semibold))
                    Text(subtitle)
                        .font(.system(size: showsProject ? 12 : 11))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    if let elapsed = Elapsed.short(row.agent.since, now: now) {
                        Text(elapsed)
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .lineLimit(1)
                TokenLines(lines: row.tokens, isLive: row.isLive)
            }
        }
        .opacity(row.isLive ? 1 : 0.6)
        .padding(.horizontal, 8)
        .padding(.vertical, showsProject ? 6 : 4)
        .background(RoundedRectangle(cornerRadius: 7).fill(isSelected ? Color.accentColor.opacity(0.18) : .clear))
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(row.action == nil ? [] : .isButton)
    }

    private var subtitle: String {
        let status = row.isLive ? row.agent.statusText : "last seen \(row.agent.statusText)"
        guard showsProject, !row.agent.project.isEmpty else { return status }
        return "\(row.agent.project) · \(status)"
    }

    private var accessibilityText: String {
        var parts = [row.agent.name]
        if showsProject, !row.agent.project.isEmpty { parts.append(row.agent.project) }
        parts.append(row.isLive ? row.agent.statusText : "last seen \(row.agent.statusText), not live")
        if let spoken = Elapsed.spoken(row.agent.since, now: now) { parts.append(spoken) }
        parts += row.tokens.flatMap { $0.map(\.text) }
        return parts.joined(separator: ", ")
    }
}

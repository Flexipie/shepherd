import ShepherdCore
import SwiftUI

/// One palette result: an agent as the queue shows it (with its project), a project with its
/// agent count and tokens, or a module's command. Matched characters of the name are bold.
struct PaletteRow: View {
    let result: PaletteResult
    let now: Date
    let isSelected: Bool

    var body: some View {
        switch result.item.kind {
        case .agent(let row):
            AgentRow(row: row, now: now, showsProject: true, isSelected: isSelected, nameHighlights: result.highlights)
        case .project(let project, let agentCount, let tokens):
            line(symbol: "folder", accessibility: projectAccessibility(project, agentCount)) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    title(project.name.isEmpty ? "Untitled" : project.name, weight: .semibold)
                    Text(agentCount == 1 ? "1 agent" : "\(agentCount) agents")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                }
                TokenLines(lines: tokens)
            }
        case .command(let command):
            line(symbol: command.symbol, accessibility: command.title) {
                HStack {
                    title(command.title, weight: .regular)
                    Spacer(minLength: 8)
                }
            }
        }
    }

    private func title(_ text: String, weight: Font.Weight) -> some View {
        Highlighted.text(text, text == result.item.title ? result.highlights : [])
            .font(.system(size: 13, weight: weight))
            .lineLimit(1)
    }

    /// A symbol in the agent glyph's place, then the content, padded like an agent row.
    private func line(symbol: String, accessibility: String, @ViewBuilder content: () -> some View) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 2, content: content)
        }
        .rowChrome(isSelected: isSelected, vertical: 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibility)
        .accessibilityAddTraits(result.item.action == nil ? [] : .isButton)
    }

    private func projectAccessibility(_ project: HerdProject, _ agentCount: Int) -> String {
        let name = project.name.isEmpty ? "Untitled" : project.name
        return "\(name), project, \(agentCount == 1 ? "1 agent" : "\(agentCount) agents")"
    }
}

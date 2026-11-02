import ShepherdCore
import SwiftUI

/// The highlighted agent's last lines, read by the app for the palette's preview.
public struct PalettePreview: Sendable, Equatable {
    public let agent: AgentID
    /// nil until the read arrives.
    public let lines: [String]?
    /// Whether its source can show its lines at all.
    public let canRead: Bool
    public let error: String?

    public init(agent: AgentID, lines: [String]?, canRead: Bool = true, error: String? = nil) {
        self.agent = agent
        self.lines = lines
        self.canRead = canRead
        self.error = error
    }
}

/// The preview of the highlighted result: an agent's last lines (the approval text while it is
/// blocked) or its final message once finished; a project's agents and tokens; nothing for a
/// command. Lines read for another agent than the highlighted one are not shown, so a quick
/// arrow never shows the previous agent's lines under the new one.
struct PalettePreviewPane: View {
    let item: PaletteItem?
    let items: [PaletteItem]
    let preview: PalettePreview?
    let now: Date
    /// The lines box's height; a longer final message is cut there.
    let height: CGFloat

    var body: some View {
        switch item?.kind {
        case .agent(let row)?:
            let shown = preview?.agent == row.agent.id ? preview : nil
            VStack(alignment: .leading, spacing: 6) {
                caption(row.agent.project.isEmpty ? row.agent.name : "\(row.agent.name) · \(row.agent.project)")
                AgentOutput(row: row, lines: shown?.lines, canRead: shown?.canRead ?? true, error: shown?.error,
                            linesHeight: height)
            }
        case .project(let project, _, let tokens)?:
            VStack(alignment: .leading, spacing: 4) {
                caption(project.name.isEmpty ? "Untitled" : project.name)
                TokenLines(lines: tokens)
                let agents = agents(in: project.id)
                if agents.isEmpty {
                    Text("No agents").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                ForEach(agents.prefix(Self.agentCount), id: \.agent.id) { row in
                    AgentRow(row: row, now: now)
                }
                if agents.count > Self.agentCount {
                    Text("and \(agents.count - Self.agentCount) more").font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
        case .command?, nil:
            EmptyView()
        }
    }

    /// Agents listed for a project, so a big one keeps the preview inside its height.
    static let agentCount = 4

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    private func agents(in project: ProjectID) -> [PanelAgentRow] {
        items.compactMap { item in
            if case .agent(let row) = item.kind, row.agent.projectID == project { row } else { nil }
        }
    }
}

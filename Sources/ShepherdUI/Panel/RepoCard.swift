import ShepherdCore
import SwiftUI

/// The checkouts of one repo in one card: the repo's name, then each checkout as a compact
/// sub-header (its label, focus dot and tokens; choosing it focuses that checkout) with its
/// agents under it.
struct RepoCard: View {
    let card: PanelRepoCard
    let now: Date
    let selection: PanelTarget.ID?
    let sectionID: String
    var jump: ((PanelAction) -> Void)?
    let perform: (PanelAction) -> Void
    let hover: (PanelTarget.ID?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            header
            ForEach(card.projects.indices, id: \.self) { index in
                let project = card.projects[index]
                Divider().padding(.horizontal, 8).padding(.vertical, 2)
                ProjectHeader(card: project, compact: true, selection: selection, sectionID: sectionID, perform: perform,
                              hover: hover)
                ProjectAgentRows(card: project, now: now, selection: selection, sectionID: sectionID, jump: jump,
                                 perform: perform, hover: hover)
            }
        }
        .cardBackground()
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

import ShepherdCore
import SwiftUI

/// The Status command's page: config problems and the herd's status lines, and a card per source.
public struct PaletteStatusPage: Sendable, Equatable {
    /// Config, plugin and hotkey problems.
    public let problems: [String]
    /// A card per place agents can come from: found or not, connected or not, and how to connect.
    public let sources: [GadgetCard]
    /// The herd's state, then each source's own lines.
    public let lines: [String]

    public init(problems: [String], sources: [GadgetCard], lines: [String]) {
        self.problems = problems
        self.sources = sources
        self.lines = lines
    }
}

/// The Status page: problems first, then the sources, then status lines. Escape goes back.
struct PaletteStatusPageView: View {
    let page: PaletteStatusPage
    let now: Date
    let maxHeight: CGFloat?

    @State private var bodyHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Status", systemImage: "stethoscope")
                .font(.system(size: 15, weight: .semibold))
            if let maxHeight {
                ScrollView {
                    content.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { bodyHeight = $0 }
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(height: min(bodyHeight, maxHeight))
            } else {
                content
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            if page.problems.isEmpty {
                Label("No problems", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            ProblemList(problems: page.problems, lines: [])
            ForEach(page.sources) { GadgetCardView(card: $0, now: now) }
            ProblemList(problems: [], lines: page.lines)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The first-run guide above the palette's rows while no agents or projects show and nothing is
/// typed: a card per place agents can come from.
struct PaletteGuideView: View {
    let guide: PanelSection
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(guide.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            ForEach(guide.items.compactMap { item -> GadgetCard? in
                if case .gadget(let card) = item { card } else { nil }
            }) { GadgetCardView(card: $0, now: now) }
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
        .padding(.bottom, 10)
    }
}

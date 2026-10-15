import Foundation
import ShepherdCore
import SwiftUI
import Testing
@testable import ShepherdUI

@MainActor
@Suite struct PaletteSnapshotTests {
    @Test func emptyQuery() throws {
        try Snapshot.check("palette", width: PaletteView.width) {
            PaletteView(content: SamplePalette.content, clock: .fixed(SampleHerd.now)) { _ in }
        }
    }

    /// Matched characters bold in an agent, a project and a command.
    @Test func withQuery() throws {
        try Snapshot.check("palette-query", width: PaletteView.width) {
            PaletteView(content: SamplePalette.content, clock: .fixed(SampleHerd.now), query: "e") { _ in }
        }
    }

    @Test func noMatches() throws {
        try Snapshot.check("palette-empty", width: PaletteView.width) {
            PaletteView(content: PaletteContent(items: [], notice: "Not connected: herdr is not running. Retrying."),
                        clock: .fixed(SampleHerd.now), query: "zzz") { _ in }
        }
    }
}

/// The sample herd as the palette indexes it: needs-you agents first, then the rest, projects,
/// then a command.
enum SamplePalette {
    static func agent(_ agent: HerdAgent, context: Int? = nil) -> PaletteItem {
        PaletteItem(id: "agent/\(agent.id)", kind: .agent(SampleHerd.row(agent, context: context)),
                    searchText: [agent.name, agent.kind ?? "", agent.project, agent.statusText], action: .jump(agent.id))
    }

    static func project(_ card: PanelProjectCard) -> PaletteItem {
        PaletteItem(id: "project/\(card.project.id)", kind: .project(card.project, agentCount: card.agents.count, tokens: card.tokens),
                    searchText: [card.project.name], action: .focusProject(card.project.id))
    }

    static let next = PaletteCommand(id: "queue.next", title: "Next agent that needs you", symbol: "arrow.forward.circle",
                                     action: .nextInQueue)

    static let content = PaletteContent(items: [
        agent(SampleHerd.blockedCodex), agent(SampleHerd.blockedClaude, context: 184_213), agent(SampleHerd.finished),
        agent(SampleHerd.working), agent(SampleHerd.idle),
        project(SampleHerd.apiCard), project(SampleHerd.webCard), project(SampleHerd.docsCard),
        PaletteItem(id: "command/queue.next", kind: .command(next), searchText: [next.title], action: .nextInQueue),
    ])
}

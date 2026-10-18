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

    /// ⌘K on an agent: its plugin actions.
    @Test func pluginActions() throws {
        let target = PluginTarget.agent(SampleHerd.finished.id)
        let commands = [("open-pr", "Open PR", "arrow.up.right.square"), ("tests", "Run tests in this worktree", "checkmark.seal"),
                        ("review", "Ask for a review", "text.magnifyingglass")]
            .map { id, title, symbol in
                PaletteIndex.commandItem(PaletteCommand(id: "plugins.demo.\(id)", title: title, symbol: symbol, keywords: ["Demo"],
                                                        action: .plugin(PluginActionRef(plugin: "demo", action: id, target: target))))
            }
        try Snapshot.check("palette-plugin-actions", width: PaletteView.width) {
            PaletteView(content: PaletteContent(items: SamplePalette.content.items,
                                                page: .actions(PluginActionsPage(title: "claude", items: commands))),
                        clock: .fixed(SampleHerd.now)) { _ in }
        }
    }

    /// What a plugin action printed, and a failure.
    @Test func pluginResults() throws {
        let text = PluginResultPage(title: "Ask for a review", text: "Review of feature/cart-totals: 8/10, safe to merge.\n\n- Tests cover the new totals.\n- One nit: rename `sum2`.")
        try Snapshot.check("palette-plugin-result", width: PaletteView.width) {
            PaletteView(content: PaletteContent(items: [], page: .result(text)), clock: .fixed(SampleHerd.now)) { _ in }
        }
        let failed = PluginResultPage(title: "Deploy", error: "Exited with 2: no credentials")
        try Snapshot.check("palette-plugin-failed", width: PaletteView.width) {
            PaletteView(content: PaletteContent(items: [], page: .result(failed)), clock: .fixed(SampleHerd.now)) { _ in }
        }
    }

    /// An idle agent's prompt: its row, its last lines, the field.
    @Test func prompt() throws {
        let stage = AgentStage(row: SampleHerd.row(SampleHerd.working, context: 184_213),
                               lines: ["Running the test suite.", "", "All 40 tests pass.", "", "> "], canReply: true, prompts: true)
        try Snapshot.check("palette-prompt", width: PaletteView.width) {
            PaletteView(content: PaletteContent(items: SamplePalette.content.items, page: .prompt(stage)),
                        clock: .fixed(SampleHerd.now)) { _ in }
        }
    }

    /// A blocked agent: its choices with ⌘ digits, and a failed send kept on screen.
    @Test func promptBlocked() throws {
        let text = """
        Bash command

          make migrate
          Apply the schema change

        Do you want to proceed?
        ❯ 1. Yes
          2. Yes, and don't ask again for make commands in /work/api
          3. No, and tell Claude what to do differently (esc)
        """
        let stage = AgentStage(row: SampleHerd.row(SampleHerd.blockedCodex), lines: text.components(separatedBy: "\n"),
                               choices: ChoiceParser.choices(in: text), canSendKeys: true, canReply: true,
                               error: "Could not send: herdr did not answer in time")
        try Snapshot.check("palette-prompt-blocked", width: PaletteView.width) {
            PaletteView(content: PaletteContent(items: SamplePalette.content.items, page: .prompt(stage)),
                        clock: .fixed(SampleHerd.now)) { _ in }
        }
    }

    @Test func newTask() throws {
        let stage = NewTaskStage(projects: [SampleHerd.api, SampleHerd.web], suggestedProject: SampleHerd.web.id,
                                 kinds: ["claude", "codex"])
        try Snapshot.check("palette-new-task", width: PaletteView.width) {
            PaletteView(content: PaletteContent(items: SamplePalette.content.items, page: .newTask(stage)),
                        clock: .fixed(SampleHerd.now)) { _ in }
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

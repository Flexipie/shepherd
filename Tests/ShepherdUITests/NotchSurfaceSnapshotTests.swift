import AppKit
import ShepherdCore
import SwiftUI
import Testing
@testable import ShepherdUI

/// The notch surface in each state, at fixed notch metrics: a 200 x 32 notch and a bar up to
/// 1000 x 300.
@MainActor
@Suite struct NotchSurfaceSnapshotTests {
    let metrics = NotchMetrics(notchWidth: 200, notchHeight: 32, maxExpandedHeight: 300, maxExpandedWidth: 1000)

    func check(_ name: String, _ mode: NotchSurfaceMode, height: CGFloat, expandedHeight: CGFloat = 0,
               tab: PanelTab = .agents, sourceLocation: SourceLocation = #_sourceLocation) throws {
        let canvas = metrics.canvas
        try Snapshot.check(name, width: canvas.width, sourceLocation: sourceLocation) {
            NotchSurfaceView(mode: mode, metrics: metrics, expandedHeight: expandedHeight, clock: .fixed(SampleHerd.now),
                             tab: tab, onStage: { _ in })
                // Only the top of the canvas, where the shape is.
                .frame(width: canvas.width, height: height, alignment: .top)
                .clipped()
        }
    }

    @Test func quietEar() throws {
        try check("notch-ear", .ear(StatusContribution(symbol: "pawprint", accessibilityLabel: "quiet")), height: 44)
    }

    @Test func attentionEar() throws {
        let status = StatusContribution(symbol: "pawprint.fill", count: 12, emphasis: .attention, accessibilityLabel: "12 waiting")
        try check("notch-ear-attention", .ear(status), height: 44)
    }

    @Test func notLiveEar() throws {
        let status = StatusContribution(symbol: "pawprint", emphasis: .dimmed, accessibilityLabel: "connecting")
        try check("notch-ear-dimmed", .ear(status), height: 44)
    }

    @Test func alert() throws {
        let item = NotchItem(agent: SampleHerd.blockedCodex, reason: .blocked, others: 2)
        try check("notch-alert", .alert(item), height: 32 + NotchPillView.contentHeight + 8)
    }

    /// The bar at its natural height, as the app sizes it.
    func checkExpanded(_ name: String, _ content: PanelContent, stage: BarStage? = nil, offersNewTask: Bool = false,
                       tab: PanelTab = .agents, sourceLocation: SourceLocation = #_sourceLocation) throws {
        let width = metrics.body(.expanded, expandedHeight: 0).width
        let bar = NotchBarView(content: content, clock: .fixed(SampleHerd.now), width: width, stage: stage,
                               offersNewTask: offersNewTask, tab: tab, perform: { _ in }, onStage: { _ in })
        // Measured with ImageRenderer, not NSHostingView: a hosting view builds real AppKit text
        // fields, whose fitting height came out a few points off under load (#54).
        let height = Snapshot.height(of: bar, width: width) + 32
        try check(name, .expanded(content, stage: stage, offersNewTask: offersNewTask), height: height + 8,
                  expandedHeight: height, tab: tab, sourceLocation: sourceLocation)
    }

    // ImageRenderer cannot draw the reply field (an AppKit text field): it shows as a yellow
    // placeholder in these references.
    @Test func stageWithChoices() throws {
        let text = """
        ⏺ I'll run the migration.

         Bash command

           make migrate
           Apply the schema change

         Do you want to proceed?
         ❯ 1. Yes
           2. Yes, and don't ask again for make commands in /work/api
           3. No, and tell Claude what to do differently (esc)
        """
        let stage = AgentStage(row: SampleHerd.row(SampleHerd.blockedCodex), lines: text.components(separatedBy: "\n"),
                               choices: ChoiceParser.choices(in: text), canSendKeys: true, canReply: true)
        try checkExpanded("notch-stage-choices", SampleHerd.content, stage: .agent(stage))
    }

    @Test func stageWithAQuestion() throws {
        let stage = AgentStage(row: SampleHerd.row(SampleHerd.blockedClaude),
                               lines: ["Two ways to store sessions:", "  a) in memory, lost on restart", "  b) in the database",
                                       "", "Which one should I use?"],
                               canSendKeys: true, canReply: true)
        try checkExpanded("notch-stage-question", SampleHerd.content, stage: .agent(stage))
    }

    @Test func stageWithContext() throws {
        let stage = AgentStage(row: SampleHerd.row(SampleHerd.working, context: 184_213),
                               lines: ["Running the test suite.", "", "> "], canReply: true, prompts: true)
        try checkExpanded("notch-stage-context", SampleHerd.content, stage: .agent(stage))
    }

    @Test func stageReadingWithAnError() throws {
        let stage = AgentStage(row: SampleHerd.row(SampleHerd.finished), lines: nil,
                               error: "Could not read: herdr did not answer in time")
        try checkExpanded("notch-stage-error", SampleHerd.content, stage: .agent(stage))
    }

    @Test func stageForAPrompt() throws {
        let stage = AgentStage(row: SampleHerd.row(SampleHerd.idle), lines: ["Updated the README.", "", "> "],
                               canReply: true, prompts: true)
        try checkExpanded("notch-stage-prompt", SampleHerd.content, stage: .agent(stage))
    }

    @Test func newTaskButton() throws {
        let projects = PanelSection(id: "projects", title: "Projects", items: [.project(SampleHerd.apiCard)], emptyText: "No projects")
        let content = PanelContent(sections: [SampleHerd.queue, projects], statusLines: ["2 working, 3 waiting"])
        try checkExpanded("notch-bar-new-task-button", content, offersNewTask: true)
    }

    @Test func newTaskForm() throws {
        let stage = NewTaskStage(projects: [SampleHerd.api, SampleHerd.web], suggestedProject: SampleHerd.web.id,
                                 kinds: ["claude", "codex"], error: "Could not start the task: herdr: unsupported agent kind x")
        try checkExpanded("notch-new-task", SampleHerd.content, stage: .newTask(stage))
    }

    @Test func expanded() throws {
        try checkExpanded("notch-expanded", SampleHerd.content)
    }

    /// The Agents tab, with the tab bar on top and the "+".
    @Test func expandedOnAgents() throws {
        try checkExpanded("notch-bar", SampleHerd.contentWithGadgets, offersNewTask: true)
    }

    /// Usage and This Mac side by side. No "+" off Agents.
    @Test func expandedOnGadgets() throws {
        try checkExpanded("notch-bar-gadgets", SampleHerd.contentWithGadgets, offersNewTask: true, tab: .gadgets)
    }

    @Test func expandedWithUsageNotRunning() throws {
        let content = PanelContent(sections: [SampleHerd.queue, SampleHerd.usageNotRunning, SampleHerd.system, SampleHerd.projects],
                                   statusLines: SampleHerd.content.statusLines)
        try checkExpanded("notch-bar-usage-not-running", content, tab: .gadgets)
    }

    /// Worktrees of one repo share a column.
    @Test func expandedWithARepo() throws {
        try checkExpanded("notch-bar-repo", SampleHerd.contentWithRepo)
    }

    @Test func expandedEmptyAndDisconnected() throws {
        try checkExpanded("notch-bar-disconnected", SampleHerd.disconnected)
    }

    /// More projects than fit: the columns past the right edge are cut off (in the app, they
    /// scroll sideways).
    @Test func expandedWithManyProjects() throws {
        try checkExpanded("notch-bar-many", SampleHerd.manyProjects)
    }

    @Test func shapesStayInsideTheCanvas() {
        let canvas = metrics.canvas
        for kind in [NotchMetrics.Kind.ear, .alert, .expanded] {
            #expect(canvas.contains(metrics.outline(kind, expandedHeight: 10_000)))
        }
        // The ear and the alert both cover the notch.
        let notch = CGRect(x: 0, y: 0, width: 200, height: 32)
        #expect(metrics.body(.ear, expandedHeight: 0).contains(notch))
        #expect(metrics.body(.alert, expandedHeight: 0).contains(notch))
        #expect(metrics.body(.expanded, expandedHeight: 10_000).height == 300)
        #expect(metrics.body(.expanded, expandedHeight: 0).width == 1000)
        // Never narrower than the notch with an ear on each side.
        let narrow = NotchMetrics(notchWidth: 200, notchHeight: 32, maxExpandedHeight: 300, maxExpandedWidth: 100)
        #expect(narrow.body(.expanded, expandedHeight: 0).width == 200 + 2 * NotchMetrics.earWidth)
    }
}

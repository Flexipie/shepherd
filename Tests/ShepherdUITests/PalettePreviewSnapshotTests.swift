import Foundation
import ShepherdCore
import SwiftUI
import Testing
@testable import ShepherdUI

/// The highlighted result's preview beside the list.
@MainActor
@Suite struct PalettePreviewSnapshotTests {
    static let blockedText = """
    Bash command

      make migrate
      Apply the schema change

    Do you want to proceed?
    ❯ 1. Yes
      2. Yes, and don't ask again for make commands in /work/api
      3. No, and tell Claude what to do differently (esc)
    """

    /// The sample list with the finished agent carrying its last message.
    static let items = SamplePalette.content.items.map { item in
        guard item.id == "agent/\(SampleHerd.finished.id)" else { return item }
        return PaletteItem(id: item.id, kind: .agent(SampleHerd.row(SampleHerd.finished, message: SampleHerd.finalMessage)),
                           searchText: item.searchText, action: item.action)
    }

    func check(_ name: String, highlight: String, preview: PalettePreview?) throws {
        try Snapshot.check("palette-preview-\(name)", width: PaletteView.listWidth) {
            PaletteView(content: PaletteContent(items: Self.items, preview: preview), clock: .fixed(SampleHerd.now),
                        selection: highlight) { _ in }
        }
    }

    @Test func agent() throws {
        let agent = SampleHerd.working.id
        let lines = ["⏺ Running the test suite.", "", "  swift test", "  Building for debugging...",
                     "  Test run with 412 tests passed after 18.2 seconds.", "", "⏺ All tests pass. Writing the changelog entry.",
                     String(repeating: "─", count: 120), "> ", String(repeating: "─", count: 120),
                     "  ⏵⏵ accept edits on (shift+tab to cycle) · 184k tokens · ctrl+t to show todos · esc to interrupt"]
        try check("agent", highlight: "agent/\(agent)", preview: PalettePreview(agent: agent, lines: lines))
    }

    @Test func blocked() throws {
        let agent = SampleHerd.blockedCodex.id
        try check("blocked", highlight: "agent/\(agent)",
                  preview: PalettePreview(agent: agent, lines: Self.blockedText.components(separatedBy: "\n")))
    }

    @Test func finished() throws {
        let agent = SampleHerd.finished.id
        try check("finished", highlight: "agent/\(agent)",
                  preview: PalettePreview(agent: agent, lines: ["PR #12 is up for review.", "", "> "]))
    }

    @Test func project() throws {
        try check("project", highlight: "project/\(SampleHerd.api.id)", preview: nil)
    }

    /// A screen narrower than the palette with its preview: the list alone, as wide as before.
    @Test func narrowScreen() throws {
        try Snapshot.check("palette-preview-narrow", width: PaletteView.width) {
            PaletteView(content: PaletteContent(items: Self.items), clock: .fixed(SampleHerd.now), maxWidth: 800) { _ in }
        }
    }
}

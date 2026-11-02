import ShepherdCore
import SwiftUI
import Testing
@testable import ShepherdUI

@MainActor
@Suite struct PaletteStatusSnapshotTests {
    /// No agents yet, on a Mac with no tmux and no herdr: the guide above the commands, none selected.
    @Test func firstRun() throws {
        let guide = PanelSection(id: "sources", title: "Where agents come from", items: SampleStatus.guide.map(PanelItem.gadget),
                                 emptyText: "")
        try Snapshot.check("palette-first-run", width: PaletteView.width) {
            PaletteView(content: PaletteContent(items: SampleStatus.commands, guide: guide), clock: .fixed(SampleHerd.now)) { _ in }
        }
    }

    /// The Status command's page with a broken config, a hotkey that would not register and a failing plugin.
    @Test func statusPage() throws {
        let page = PaletteStatusPage(problems: SampleStatus.problems, sources: Array(SampleStatus.guide.dropLast()),
                                     lines: ["0 working, 0 waiting", "reports in ~/.local/state/shepherd/reports"])
        try Snapshot.check("palette-status", width: PaletteView.width) {
            PaletteView(content: PaletteContent(items: [], page: .status(page)), clock: .fixed(SampleHerd.now)) { _ in }
        }
    }

    /// Problems in the footer point to the Status page.
    @Test func problemNotice() throws {
        try Snapshot.check("palette-problem-notice", width: PaletteView.listWidth) {
            PaletteView(content: PaletteContent(items: SamplePalette.content.items, notice: "3 problems, see Status",
                                                noticeIsProblem: true),
                        clock: .fixed(SampleHerd.now)) { _ in }
        }
    }
}

@MainActor
enum SampleStatus {
    static let guide = [
        GadgetCard(id: "tmux", title: "tmux", detail: "not installed",
                   lines: ["Install tmux and run your agents in its panes to see them here."]),
        GadgetCard(id: "claude", title: "Claude Code", detail: "found", lines: [
            "For exact status in any terminal, tmux and herdr included, run this in Terminal. It shows the change before writing it.",
            "/Applications/Shepherd.app/Contents/MacOS/shepherd-report install claude",
        ]),
        GadgetCard(id: "herdr", title: "herdr", detail: "not running", lines: ["If you use herdr, its agents show here once it starts."]),
        GadgetCard(id: "demo", title: "Demo", detail: "made-up agents",
                   lines: ["To see Shepherd with a herd first, right-click the menu bar icon and choose Try Demo."]),
    ]

    static let commands = [
        PaletteCommand(id: "app.status", title: "Status", symbol: "stethoscope", action: .status),
        PaletteCommand(id: "app.config", title: "Open config file", symbol: "doc.text", action: .openConfig),
        PaletteCommand(id: "plugins.folder", title: "Open plugins folder", symbol: "folder", action: .openPluginsFolder),
    ].map { PaletteIndex.commandItem($0) }

    static let problems = [
        "config: unknown key \"hotkey\"",
        "config: hotkeys.palette: \"option+space\" is already in use",
        "plugin deploys: listActions exited with status 1",
    ]
}

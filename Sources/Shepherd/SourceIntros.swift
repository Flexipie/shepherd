import HerdrSource
import ReportSource
import ShepherdCore
import TmuxSource

/// The first-run guide's words for each place agents can come from, in the order PRD "Sources"
/// gives: tmux and agent reports for any terminal, then herdr. Claude Code is left out when it is
/// not on this Mac.
@MainActor
enum SourceIntros {
    static func make(tmuxInstalled: Bool, claude: ClaudeSetup) -> [SourceIntro] {
        var intros: [SourceIntro] = []
        if tmuxInstalled {
            intros.append(SourceIntro(
                id: "tmux", name: "tmux", source: TmuxSource.sourceID,
                on: .init("found", "Run Claude Code or Codex in a tmux pane and it shows here, its state read from the screen."),
                off: .init("starting", "Looking for tmux servers.")))
        } else {
            intros.append(SourceIntro(
                id: "tmux", name: "tmux", found: false,
                on: .init("found", ""),
                off: .init("not installed", "Install tmux and run your agents in its panes to see them here.")))
        }
        if claude != .notFound {
            intros.append(SourceIntro(
                id: "claude", name: "Claude Code", found: claude == .hooksInstalled,
                on: .init("reports on", "Each session reports its own exact status, in any terminal."),
                off: .init("found", "For exact status in any terminal, run shepherd-report install claude. It shows the change before writing it.")))
        }
        intros.append(SourceIntro(
            id: "herdr", name: "herdr", source: HerdrSource.sourceID,
            on: .init("connected", "Agents in herdr panes, with exact status: jump to them, reply and start new tasks."),
            off: .init("not running", "If you use herdr, its agents show here once it starts.")))
        return intros
    }
}

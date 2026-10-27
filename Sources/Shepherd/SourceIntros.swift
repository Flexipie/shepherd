import HerdrSource
import ReportSource
import ShepherdCore
import TmuxSource

/// The first-run guide's words for each place agents can come from, in the order PRD "Sources"
/// gives: tmux and agent reports for any terminal, then herdr. A source the config leaves out has
/// no card, nor does Claude Code when it is not on this Mac or reports are left out.
@MainActor
enum SourceIntros {
    /// `sources` is the config's source order; `tmuxInstalled` whether tmux was found for it;
    /// `canTryDemo` whether the menu offers Try Demo, which then gets the last card.
    static func make(sources: [String], tmuxInstalled: Bool, claude: ClaudeSetup, canTryDemo: Bool) -> [SourceIntro] {
        var intros: [SourceIntro] = []
        if sources.contains("tmux") {
            intros.append(tmuxInstalled
                ? SourceIntro(id: "tmux", name: "tmux", source: TmuxSource.sourceID,
                              on: .init("found", "Run Claude Code or Codex in a tmux pane and it shows here, its state read from the screen."),
                              off: .init("starting", "Looking for tmux servers."))
                : SourceIntro(id: "tmux", name: "tmux", found: false, on: .init("found", ""),
                              off: .init("not installed", "Install tmux and run your agents in its panes to see them here.")))
        }
        if sources.contains("report"), claude != .notFound {
            intros.append(SourceIntro(
                id: "claude", name: "Claude Code", found: claude == .hooksInstalled,
                on: .init("reports on", "Each session reports its own exact status, in any terminal. In tmux or herdr it stays one row you can answer."),
                off: .init("found", "For exact status in any terminal, tmux and herdr included, run shepherd-report install claude. It shows the change before writing it.")))
        }
        if sources.contains("herdr") {
            intros.append(SourceIntro(
                id: "herdr", name: "herdr", source: HerdrSource.sourceID,
                on: .init("connected", "Agents in herdr panes, with exact status: jump to them, reply and start new tasks."),
                off: .init("not running", "If you use herdr, its agents show here once it starts.")))
        }
        if canTryDemo {
            intros.append(SourceIntro(id: "demo", name: "Demo", on: .init("", ""), off: .init(
                "made-up agents", "To see Shepherd with a herd first, right-click the menu bar icon and choose Try Demo.")))
        }
        return intros
    }
}

# Changelog

What changed in each release of Shepherd, newest first. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow
[Semantic Versioning](https://semver.org/).

## [0.1.0] - Unreleased

The first release: a menu bar item and a piece of the notch for a herd of coding agents, wherever
they run.

### Added

- **See your herd at a glance.** A paw in the menu bar and around the notch (a small floating pill
  on a Mac without one). It turns orange with a count when agents need you; hover the notch for a
  wide bar with the needs-you queue first (blocked, then finished, longest waiting first), then a
  column per project with each agent's state and time in state. Worktrees of one repo share a
  column.
- **Agents from any terminal.** Three sources: herdr, tmux and agent reports. tmux needs no setup:
  Claude Code and Codex panes are recognised from their screen. `shepherd-report install claude`
  adds hooks so Claude Code reports its exact state from any terminal, and any agent or script can
  report its own with `shepherd-report report`. With no agents yet, the panel says where agents
  come from and what each source needs.
- **Try it before your own agents.** Try Demo in the menu bar icon's right-click menu (or
  `make demo`) runs Shepherd on a made-up herd, with approvals, finished work and questions to
  click through. It touches nothing of yours; Leave Demo goes back.
- **Act without switching to the terminal.** Answer an approval from the notch with buttons or
  digit keys, reply to a blocked agent, prompt an idle one, or start a new task in a fresh
  worktree. Works for agents under herdr and tmux. Jumping brings the right terminal forward, even
  from another Space.
- **A palette on ⌥Space.** Fuzzy search over agents, projects and commands from any app; Return
  jumps, Tab opens an agent's prompt page. ⌃⌥⌘N jumps to the next agent that needs you.
- **Judge finished work from the row.** Claude Code agents under herdr show their context size
  and, once they stop, their final message, in full on the stage and in the palette.
- **Gadgets.** A second tab with plan usage from [OpenUsage](https://github.com/robinebers/openusage)
  and the Mac's own CPU and memory, read only while the tab shows.
- **Yours to shape.** `~/.config/shepherd/config.json`, applied on save: the columns and gadgets
  each tab shows and their order, tmux screen patterns for new agent kinds, hotkeys, token styling
  (read from herdr's own config), and opt-in notifications with Jump and Reply. Which sources run
  applies at the next launch.
- **Plugins.** A folder with a small manifest adds palette actions for the herd, a project or an
  agent, sets tokens on rows, and runs on events (agent started, blocked, finished, task started).
- **Light on the Mac.** No polling: Shepherd waits for events. Measured at idle it uses 0% CPU
  and about 14 MB of memory; `make perf` fails if idle goes over 0.5% CPU or 60 MB.

### Known limits

- No signed download yet: build from source (macOS 26, Swift 6.2). A notarised DMG and a Homebrew
  cask come next ([#56](https://github.com/Flexipie/shepherd/issues/56)).
- Context size and the final message need herdr: Claude Code agents in tmux or reporting through
  hooks show their state only, and Codex shows neither yet.
- An agent seen only through reports shows its state, but can't be answered, prompted or jumped
  to. Under tmux, a Claude Code agent with the hooks installed shows as a report, so the hooks cost
  it those actions: skip `install claude` there for now.
- Codex shows up under herdr and tmux; it has no hook install yet, so in other terminals it
  appears only when something runs `shepherd-report report` for it.

[0.1.0]: https://github.com/Flexipie/shepherd/releases/tag/v0.1.0

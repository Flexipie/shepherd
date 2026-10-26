# Shipped

Oldest first.

- Repo skeleton: SwiftPM package with `HerdrKit`, `ShepherdCore`, `ShepherdModules` and the
  `Shepherd` app target; socket path resolution with tests; menu bar placeholder; `make app`
  bundles an ad-hoc signed menu-bar-only `.app`.
- Minimum macOS raised to 26 (Swift tools 6.2), so on-device models, speech and Liquid Glass need
  no fallbacks.
- First commit, public repo at github.com/Flexipie/shepherd.
- Milestone 0, foundations: CI on GitHub Actions (macOS 26); `HerdrFake`, a fake herdr on a real
  Unix socket that mimics herdr's quirks; a fixture recorder and sanitiser (`make fixture`) with
  one recorded fixture; `FakeHerdr`, a fake driven from stdin for trying the app.
- Milestone 1, live connection, menu bar and notch base: `HerdrKit` client (one request per
  connection, GCD read source for the event stream), lenient models, `SubscriptionPlanner`
  (global-only first, per-pane upgrade, make-before-break), `SessionEngine` (debounced,
  serialized snapshot refresh, `events_lost` and reconnect with a socket-folder watcher),
  `TransitionTracker` (time in state, exact or "no later than"), `SessionStore`; the settled
  `ShepherdModule` protocol with `StatusModule` and `NotchModule`; the menu bar item; the notch
  pill with a floating fallback; jumping to an agent focuses its pane and brings the hosting
  terminal forward. Idle: 0% CPU, about 53 MB RSS.
- Milestone 1, the source seam: the source-neutral herd model, `AgentSource` and `HerdStore` in
  `ShepherdCore`; `HerdrSource` as the only bridge to `HerdrKit` (its `SessionStore` removed);
  modules and the app see only the herd model. `TransitionLog` keeps observed transitions on disk
  (with project labels, capped at 5,000) and restores exact times in state after a restart.
- Milestone 2, the panel: projects (herdr workspaces) in the herd model with `workspace.focus`;
  token layouts and a styler with herdr's sidebar rule semantics, read from herdr's own config by
  a small TOML reader, overridable in Shepherd's config, with a contrast guard for light mode;
  `~/.config/shepherd/config.json` with per-key leniency and hot reload; the `queue` and
  `projects` modules and a `ModuleRegistry` built from config; the `ShepherdUI` target with
  snapshot tests; the panel window under the status item (glass, keyboard navigation, closes on
  Escape, outside click, Space change or jump); the global "next" hotkey (⌃⌥⌘N). Idle with the
  panel closed: 0% CPU over 30 s; open: one wake a minute; about 65 MB RSS, flat over ten opens.
- The notch surface: one black shape around the notch that morphs between a paw ear (orange with
  a count when agents need you), the needs-you pill, and the full panel on hover. Hover never
  takes typing from the terminal; a click inside gives it the keyboard; Escape, a click elsewhere
  or a jump folds it. The window follows the shape, so nothing transparent sits over the menu
  bar at rest. `PanelContentSource` feeds both panels. Idle with the ear showing: 0% CPU over
  30 s, about 62 MB RSS.
- The notch bar: hovering the notch grows a wide, short bar along the top of the screen instead
  of a tall panel. The needs-you queue is pinned on the left, then one column per project
  (`BarColumn`, shared by the view and keyboard navigation), scrolling sideways when there are
  many; arrows move across the grid. The menu bar panel stays vertical. Idle with the ear
  showing: 0% CPU over 30 s, about 54 MB RSS.
- Answer from the notch: choosing a needs-you agent in the bar opens its stage, with its last
  visible lines (`agent.read`, only while open), its choices parsed by `ChoiceParser` as buttons
  and digits (`agent.send_keys`), Return and Escape as a fallback, and a reply field
  (`pane.send_input`). Sources gained `read`, `sendKeys` and `sendText`, through `HerdStore` and
  `AgentActions`; herdr's errors reach the stage in words. FakeHerdr answers all three.
- Prompt and new task: every agent row in the bar opens its stage; an agent that is not blocked
  gets a prompt field (`agent.prompt`). A "+" after the project columns opens a new task form
  (project, agent, optional branch, prompt): `worktree.create`, `agent.start` with
  `agents.<kind>.args` from config, then `agent.prompt`, and the new agent's stage opens. A
  failed step says what earlier steps left behind. FakeHerdr answers all of it.
- Notifications, opt-in: the `notifications` module posts a macOS notification with Jump and
  Reply when an agent blocks while you are not looking, and withdraws it when the agent moves
  on. `"notifications": "off" | "on" | "auto"` (off by default; auto defers to herdr's own system
  toasts). Permission is checked before every post and a refusal shows in the footer.
- Quick jump from the bar: a hovered or selected agent row shows an arrow that jumps straight to
  the agent; ⌘-click and ⌘Return do the same. A plain click or Return still opens the stage.
- Usage gadget: a `usage` column next to the needs-you queue (and a section in the menu bar
  panel) with plan limits for every account OpenUsage tracks, both Claude accounts and Codex, read
  from OpenUsage's local API by the `OpenUsageSource` target. No credentials, nothing sent off
  the machine, and reads only while a panel is open, once per OpenUsage refresh. Idle with the
  bar closed: 0% CPU, about 55 MB RSS, no connections.
- System gadget: a `system` column ("This Mac") after usage with the whole Mac's CPU and memory
  as two bars, from Mach host statistics in the `SystemSource` target. It samples every 2 s only
  while the bar or panel is open; closed, no task and no system calls.
- Context size: Claude Code rows and the stage show the agent's context size ("184k"), read by
  the `context` module through the `ClaudeSessionSource` target from the tail of the session
  file herdr's `agent_session` points at, only while the bar or panel is open (on opening and on
  a status change), cached by size and modification date.
- Palette: ⌥Space (`hotkeys.palette`, `null` turns it off; ⌃⌥⌘Space at first, which is hard to
  press on a Swedish keyboard) opens a search field centred on the screen under the mouse, over
  any app, without taking the frontmost app's place. It finds live agents, projects and module
  commands by name, kind, project, status and token values with a fuzzy match (word starts, runs
  and prefixes first, matched characters bold); with no query, agents that need you come first.
  Return jumps or focuses the project, Escape closes. Modules contribute commands
  (`ShepherdModule.commands`); `queue` offers "Next agent that needs you". `HotKeyCenter` handles
  several named hotkeys and reports a clash between them. Idle with the palette closed: 0% CPU
  over 30 s, about 56 MB RSS; the first open adds about 45 MB RSS (footprint: about 15 MB idle,
  about 9 MB more on first open).
- Prompt and new task in the palette: Tab (or →) on an agent opens its prompt page (its row, its
  last eight lines, the field), from a second `StageModel` that reads only while the page shows.
  Return replies to a blocked agent and prompts any other; success closes the palette, a failure
  stays with the text kept. Choices are buttons with ⌘1 to ⌘9 (`ChoiceButtons`, shared with the
  notch stage). `projects` contributes "New task…" and "New task in <project>", which open the
  new task form in the palette with the project picked; a started task becomes the new agent's
  prompt page. Escape or ← in an empty field goes back with the query kept; the page keys are
  the pure `PaletteMode` in Core.
- Palette prompt focus: after Tab the prompt field takes the keyboard (focusing in `onAppear` came
  too early once the search field it replaced was gone, so typing went nowhere). The field sits
  in a visible box and stays enabled while a send is on its way. Default hotkey moved to ⌥Space.
- Agents | Gadgets tabs: the menu bar panel and the notch bar have a tab bar at the top (Agents,
  the queue and projects, where each opening starts; Gadgets, usage and This Mac), clicked or
  ⌘1 and ⌘2. `PanelSection.tab` says where a section goes, so gadgets need no central list.
  `Presence` tracks the tab each surface shows; `usage` and `system` read only while Gadgets
  shows and `context` only while Agents shows. No gadgets enabled, no tab bar.
- Worktrees grouped by repo: herdr's `worktree` object on workspaces is decoded
  (`Workspace.worktree`) into `HerdProject.repo`. `projects` puts two or more checkouts of one
  repo in one `PanelRepoCard` (one card in the panel, one column in the bar) at the first one's
  place, main checkout first, each with a sub-header (label, focus dot, tokens, a branch glyph
  for worktrees) that focuses it; a checkout with one agent is one row (its label, the agent's
  state and time) that jumps to the agent. Keyboard navigation walks each checkout's header and agents;
  the palette finds every worktree by the repo's name. FakeHerdr has `repo <workspace> [name]`,
  and its `worktree.create` makes a linked worktree of the source's repo.
- Plugins, first slice: a folder in `~/.config/shepherd/plugins/` with a `shepherd-plugin.json`
  adds actions (global, project, agent), also listed at runtime by `listActions`. Global actions
  are palette commands; ⌘K on an agent or project lists its own; a result page shows printed
  text or the failure. A JSON `tokens` result sets tokens on the row for any source. Read when
  the palette opens, run off the main actor with a timeout; `plugins.disabled` turns one off.
  `HerdProject.path` carries the checkout. Examples: herdr's plugin actions, and a diff stat.
- Plugins, events: a manifest's `events` lists what a command runs for (`agent.started`,
  `agent.blocked`, `agent.finished`, `task.started`). `HerdStore.events()` delivers every herd event
  to each subscriber in order, without drops; `PluginHost` runs the listed plugins with the agent's
  environment and `SHEPHERD_EVENT`. Debounced 5 s per plugin, agent and event, with one queued run
  when an event arrives during another. Output is ignored; a failure shows under `plugins` in the
  footer. Not tied to the `plugins` module, so it runs whenever the plugin is on.
- Agent reports: `shepherd-report report --status working|blocked|done|idle|closed` (`--message`,
  `--question`, `--agent`, `--kind`, `--from-hook` for a Claude Code hook's stdin) writes one JSON file per
  agent to the spool (`SHEPHERD_SPOOL_DIR`, else `~/Library/Application Support/Shepherd/reports`), written
  to a temporary file and renamed into place. `ReportSource` watches the folder (no polling), reads it off
  the main actor, and maps reports to agents with a pure tracker: a working report silent for 15 minutes
  shows unknown, blocked and done are removed after 24 hours, `closed` removes the agent. Transitions after
  startup feed notifications and plugin events unchanged. Identity: `--agent`, `SHEPHERD_AGENT_ID`, the tmux
  pane, the hook session, then the working directory. `HerdAgent` carries `message` and `question`, not yet
  shown. The CLI is built as `shepherd-report` until its name is settled (`shepherd` collides with the app
  binary on a case-insensitive disk); `scripts/bundle.sh` copies it into the app.
- tmux source (roadmap "Next: any terminal agent", step 2): an agent in a tmux pane shows with no
  herdr and no hooks. `TmuxKit` wraps the `tmux` command (pane listing with a fixed format,
  `capture-pane`, `send-keys -l` and key names, `select-window` and `select-pane`), reads control
  mode (`tmux -C attach-session` with `refresh-client -f ignore-size`, so attaching never resizes a
  window) and takes one `ps` snapshot when a pane exists. `TmuxSource` matches a pane to an agent
  when a process under its shell is named `claude` or `codex` (a script run by an interpreter is
  named by the script), reads the pane's screen with patterns per kind in code, and labels the state
  inferred. Approval prompts are `blocked` (`ChoiceParser`), the `esc to interrupt` hint is
  `working`, the idle input line is `idle`, anything else `unknown`. A change waits two seconds
  before it shows, except a prompt. Output from a pane is the only trigger for a read (debounced
  300 ms), a window or session change lists the panes again, and the socket folder is watched
  while no server is up. Answering a prompt, reading, prompting an idle agent and focusing use the
  same actions as herdr; the private-server tests cover them, and real agents are on the by-hand list. A report from the same pane (`tmux:<socket>:<pane>`) replaces
  the screen row, and screen readings are not announced to notifications or plugin events. The
  source is added only when `tmux` is installed. Tests run a private tmux server with fake `claude`
  scripts; `SHEPHERD_LIVE=1` reads the real servers.
- Shared row and card components and a surface layer (#30): `ShepherdUI` is split into
  `Components` (row chrome, the choosable row with its `RowContext`, the card fill), `Items` (one
  view per item kind, `PanelItemView` the one switch) and `Surfaces` (panel, notch, palette, and
  the `Clocked` clock they share). `PanelItem.usage` became `PanelItem.gadget(GadgetCard)`, so
  This Mac no longer poses as a usage account and a gadget made of meters and lines touches only
  its module. No pixel changed: every snapshot matches its reference.
- `sources` in config (#35): `AppController` builds its sources from the `sources` list (default
  herdr, report, tmux, in that order), so herd order follows the list and a source can be left
  out. The tmux screen patterns moved from code into config data (`ScreenPatterns`, with Claude
  Code and Codex as built-in defaults): per agent kind a process name and `blocked`, `working` and
  `idle` regex lists over the screen's footer. Users edit a built-in kind or add their own, and
  pattern edits apply on save. A changed list of sources applies at the next launch and the
  footer says so.
- tmux agents grouped by git repo and worktree (#33): `GitCheckout` (in `ShepherdCore`) reads the
  `.git` entries above a folder with no `git` process: a `.git` folder is a main checkout, a
  `.git` file points to a linked worktree whose `commondir` names the repo's git dir, and that
  common dir (its real path) is the repo key. A tmux pane's project is now its checkout's top
  folder, so panes anywhere in one checkout share a card, and it carries the repo, so the projects
  module groups a repo's main checkout and worktrees into one card as it does for herdr. Outside
  git a pane's folder is still its project. A report from a folder inside a screen's checkout
  hides that checkout's card once no screen agent is left in it. `HerdAgent.cwd` keeps the pane's
  own folder, so a plugin still gets it as `SHEPHERD_CWD`.
- Hook install (#32): `shepherd-report install claude` adds Shepherd's hooks to Claude Code's
  settings (`$CLAUDE_CONFIG_DIR/settings.json`, else `~/.claude/settings.json`): `SessionStart`
  idle, `UserPromptSubmit` and `PostToolUse` working, `Notification` on a permission prompt or an
  MCP question blocked, `Stop` done, `SessionEnd` closed, each running `shepherd-report report
  --status <s> --kind claude --from-hook` by its bare name, found on PATH. When it is not on the
  shell's PATH, install says so before asking, with an `ln -s` for this binary into the first folder
  on PATH the user can write, else into `/usr/local/bin` with sudo (Claude Code runs hooks with the
  PATH it was started with). It prints the change as a unified diff, asks before writing (`--yes`
  when stdin is not a terminal, `--print` to only show it), copies the file to
  `settings.json.shepherd-backup-<time>` beside the link, and writes through a symlink so a dotfiles
  link stays. It refuses a link to a missing file and a file changed while it asked. A hook's usage
  error exits 1, never 2, which would block Claude. Only hook entries whose program is
  `shepherd-report` or `shepherd` followed by `report` are added or removed; installing again
  replaces an older form (an absolute path) and is otherwise a no-op. `uninstall claude` removes
  exactly those entries, and the groups and events they leave empty. The file is read with key order
  and numbers kept and printed as Claude Code writes it, so for a file Claude Code wrote the diff
  holds only Shepherd's lines. A file that is not strict JSON (comments, trailing commas, a repeated
  key) is refused untouched. Codex waits until its `notify` format is confirmed.
- Memory budget is physical footprint (`docs/PRD.md`, "Performance budget"); the RSS figures above
  count shared system frameworks. Panel windows turn Writing Tools off in their field editor, so
  the palette's first focus no longer loads WebKit and a few hundred other frameworks; spell check,
  autocorrect and completion are unchanged. Against fake herdr: footprint about 14 MB idle and 24 MB
  after the bar and the palette, before and after; RSS after the palette about 77 MB, down from 98.
- `TerminalLocator` is source-neutral (#37): it finds the app hosting any process by walking up
  its ancestors, from whatever pids a source gives it, with the "is it an app" check passed in
  (Core has no AppKit). Finding herdr's processes, and why walking up from them skips the server,
  moved into `HerdrSource` (`HerdrProcesses`). herdr and tmux call the same entry point.
- Snapshot tests measure the notch bar's height with `ImageRenderer` instead of an `NSHostingView`.
  The hosting view built real AppKit text fields, whose fitting height came out a few points off
  under load (#54), so a stage or new task snapshot failed on size alone. The height is rounded up
  like `fittingSize`, so every reference is unchanged.
- Idle budget check: `make perf` (`scripts/perf.sh`) builds the release app, runs it against fake
  herdr with only the herdr source and every path in a temp folder, and fails if CPU over a 30 s
  idle window averages more than 0.5% or the physical footprint is over 60 MB (`PERF_SECONDS`,
  `PERF_CPU_LIMIT`, `PERF_MEMORY_LIMIT_MB` override them). First run: 0.00% CPU, 14.0 MB. The
  footprint after opening the bar and the palette is still measured by hand.
- First run (#36): Shepherd without herdr no longer reads "Not connected: herdr is not running" or
  dims its glyph. A source that is not on the Mac or not running is `absent` (herdr: no socket
  file), which the herd's state leaves out. While no agent shows, the Agents tab (and the notch
  bar) starts with "Where agents come from": a card each for tmux (found, or not installed),
  Claude Code (when its settings folder exists: hooks on, or the `shepherd-report install claude`
  command) and herdr (connected or not running), saying what each gives. Detection only reads;
  nothing is written or remembered, and with no config file everything runs on defaults.
- Choose and order columns and gadgets from config (#31): a `layout` key, separate from
  `modules`. `layout.agents` and `layout.gadgets` list the sections each tab shows, in order
  (`PanelLayout.arrange`, applied once in `PanelContentSource`, so the menu bar panel, the bar's
  columns and keyboard navigation agree); `layout.projects` puts the named project and repo
  columns first (`ProjectsModule`). Left out, nothing changes. Unknown ids are reported under
  `layout`. Hiding a gadget no longer means listing every other module.
- An agent's final message (#41): `ClaudeSessionSource` reads the text of the latest turn's last
  main-thread assistant entry in the same tail walk as the context size (none after a newer
  prompt, interruption or API error), and `context` keeps it beside the size, read again when the
  agent's status or session changes. A row shows it on one line under the title once the agent
  stops working; the stage and the palette's prompt page show it whole, inline Markdown drawn, in
  place of the last lines while the agent is idle or done. The palette now counts as showing
  Agents, so opening it alone reads sessions. Codex's session file
  (`task_complete.last_agent_message`) is a follow-up.
- tmux starts new tasks (#34): the "+" and the palette's "New task" now work for tmux projects.
  `git worktree add -b` from the project's checkout into `<repo>-<branch>` next to the repo, then a
  `new-window -d` after one of the project's agents running the agent with its args and the prompt
  as separate arguments (no shell quoting; `--` before the prompt), then the user's shell. git and the
  window get the server's PATH, not the app's. A left-out branch is the kind and a random suffix; a
  project outside git, a folder already there, an agent not on the server's PATH and a prompt past
  about 15 KB (tmux's command limit) are refused before anything is made. A step that fails after
  the worktree was made says it is there.
- Demo mode (#38): `Shepherd --demo`, `make demo`, or Try Demo in the status item's right-click
  menu (it reopens Shepherd in demo mode; Leave Demo goes back) runs on a fixed made-up herd: three
  herdr projects from `HerdrFake` (an approval waiting, one finished, one working, one idle), two
  Claude Code reports (one working, one asking a question) and two screen-read tmux agents,
  through the real herdr and report sources. A "Demo herd" card tops the Agents tab and the menu
  says so. It reads and writes nothing of the user's: no herdr, tmux, config, transition log,
  plugins, notifications, usage or session files; the socket and spool are fixed paths under `/tmp`. The
  first-run guide's last card points to it. Idle in demo: 0.0% CPU, 24 MB footprint.
- README for any terminal agent (#39, and the text of #58): it opens with a short pitch and the
  notch bar's snapshot, then a table of where agents come from (tmux, agent reports, herdr) and
  what each gives, stating tmux as what the screen features need. Install is build from source
  (`make app`; the Claude Code hooks optional, for agents outside tmux and herdr), with no signed
  build or Homebrew yet. A Privacy section lists the one loopback request (OpenUsage), no telemetry, and
  every file Shepherd reads and writes, each checked against the code. The feature tour is tighter
  and no longer assumes herdr.

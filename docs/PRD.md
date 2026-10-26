# Shepherd: product and architecture

The why, the audience and the quality bar are in [VISION.md](VISION.md). This doc is the how.

## What it is

A native macOS app in the menu bar and the notch for running a herd of coding agents. Agents
reach Shepherd through **sources**. herdr is the first and richest one: it already knows the
state of every workspace, pane and agent, and exposes it on a local socket. Shepherd gives that
state a richer surface than a terminal can: full colour, any layout, no length limits, native
notifications, and actions from any app.

Shepherd is not person-specific. Anything personal (Linear tickets, PR numbers, review verdicts)
reaches Shepherd as **tokens** published by plugins, and Shepherd renders tokens generically.
Personal actions are config, not code.

## Goals

- Clean, small, fast base: near-zero CPU when idle (under 0.5%), under 60 MB of memory as
  physical footprint (see "Performance budget").
- Easy to extend: one feature is one module; most customisation is JSON config.
- Correct under load: follows herdr's documented recovery protocol, never shows silently stale
  state.
- Uses what a modern Mac already has (on-device models, speech, Spotlight, Focus) before reaching
  for anything else, and only where it helps the core job.

## Non-goals

- Reading terminal screens or agent hooks outside a source adapter (see "Sources").
- Bundling or requiring a model, local or cloud. Nothing waits on one (see "Intelligence").
- Cross-platform, or macOS before 26. Shepherd targets macOS 26 and later so it can use the
  on-device model, `SpeechAnalyzer`, Liquid Glass and current App Intents without fallbacks for
  old systems.
- Talking to Linear, GitHub or daisy directly. Plugins publish tokens; Shepherd reads them.
- Sending data off the Mac by default. Any network use is a user-configured action or endpoint.

## Inspiration: Coucou

[Coucou](https://github.com/Louis-CFM/coucou) (MIT) is a notch companion for agent sessions.
Ideas we take: the notch panel technique (borderless non-activating `NSPanel` just above the main
menu window level, on all Spaces, mouse-transparent until hovered; notch detected via
`NSScreen.safeAreaInsets.top`, with a top-bar fallback on Macs without one), toggleable "pills",
and a character with personality. What we avoid: a closed enum of pills, very large files, and
hook handling spread through the app. How Shepherd positions itself against Coucou is in
[STRATEGY.md](STRATEGY.md).

## Sources

A source is where agents come from. Modules and surfaces never see a source's wire types; they
see one **herd model**: agents with a state (`idle`, `working`, `blocked`, `done`, `unknown`),
their workspace or project, time in state, tokens, and the transitions Shepherd observed.

- Each source declares its **capabilities**: focus, read output, prompt, send keys, send text, approve,
  start an agent, create a worktree. Surfaces hide what a source cannot do instead of failing.
- Each source owns its own connection, recovery and decoding. The "Data flow" rules below are
  herdr's; another source follows the same spirit (no polling where events exist, never show
  stale state as current).
- Hooks and screen reads are allowed only inside a source adapter. Nothing outside the adapter
  knows how a source gets its state.
- Screen reads (tmux `capture-pane`) match per-agent patterns. A state from a match is labelled
  inferred; a state from a report or an API is not. Patterns for Claude Code and Codex ship as
  built-in defaults (`ScreenPatterns.builtin`); config can edit them or add agents (see "Config").
- Agent reports (`shepherd report`) are the generic way for any agent to state its own status,
  from its own hooks, rules or skills. Shepherd never edits an agent's settings without showing
  the change first: `shepherd-report install claude` prints a diff, asks, backs the file up and
  touches only entries that run `shepherd-report report`.
- Order: tmux and agent reports first (any agent in a terminal), then herdr and Claude Code's
  session files as optional adapters, then cloud agents through their APIs (opt-in, the first
  network-using sources).

What a Claude Code source can use (checked October 17, 2026 on Claude Code 2.1.299, read only):

- `claude agents --json` (add `--all` for completed background sessions) prints every Claude
  session on the machine, interactive and background, as a JSON array and exits: `id`,
  `sessionId`, `name`, `kind` (`interactive` or `background`), `cwd`, `pid`, `startedAt`, `status`
  (`busy`, `idle`, `waiting`), `state` (`blocked`, `done`, `failed`) and `waitingFor`. It is a
  snapshot, not a stream; one read takes about 0.2 s and 0.16 s of CPU.
- Claude Code keeps one file per running process in `~/.claude/sessions/<pid>.json`, rewritten as
  its status changes (`status`, `statusUpdatedAt`). The plan: watch that directory as the event
  (no polling), then re-read with `claude agents --json`, debounced, as herdr's events trigger a
  `session.snapshot`. The file's fields are internal, so only the change matters, not its
  contents. The `.key` files beside them are never read.
- `claude --bg "<prompt>"` starts a background session in its own worktree; `claude attach`,
  `logs`, `stop` and `rm` manage it. That gives start, read and focus (attach in a terminal).
- Interactive sessions include ones running inside herdr panes, so one agent can appear from
  both sources. They share Claude's session id (herdr's `agent_session`), which is how the store
  will tell them apart.
- Agent view is a research preview: the source must tolerate missing fields and a missing
  command, and say so in its status line.

As built:

- `ShepherdCore` holds the herd model (`HerdAgent`, `HerdProject`, `HerdStatus`, `Since`,
  `HerdTransition`, `SourceState`, `SourceCapabilities`), the `AgentSource` protocol and
  `HerdStore`, which merges every source, orders the needs-you queue across them, and routes focus
  to the owning source. Agent and project ids are namespaced by source (`herdr:w1:p1`,
  `herdr:w1`). A project is where agents work (for herdr, a workspace); projects without agents
  are kept, since they are somewhere to go. Project tokens stay on the project and agent tokens
  on the agent. `HerdProject.repo` (`HerdRepo`: a key, a name, whether it is a linked checkout)
  says which git repo a project is a checkout of; herdr fills it from the workspace's
  `worktree`, and tmux from `GitCheckout` (the `.git` entries on disk, with the common git dir
  as the key).
- `HerdrSource` is the only target that imports both `HerdrKit` and `ShepherdCore`. It adapts
  herdr's session to the herd model, implements focus (`agent.focus`, then the hosting terminal
  forward) and project focus (`workspace.focus`, then the terminal), reports the terminal as its
  host app, and supplies its own status lines (version, protocol warnings, the socket path while
  disconnected, problems in herdr's config). It declares `focus` and `focusProject`. It also
  reads herdr's sidebar config and sends it as the source's token layout (see "Tokens").
- A source that is not on this Mac or not running at all is `SourceState.absent`, not disconnected:
  it has nothing to show and nothing is wrong, so `HerdStore.overallState` leaves it out and the
  menu bar glyph is not dimmed for it. herdr is absent while its socket file is missing; a socket
  left by a herdr that crashed is still a disconnection (its last state shown dimmed); an absent herdr
  keeps no agents. It connects on its own when herdr starts.
- First run: the app detects what is on the Mac, read only (tmux on PATH, herdr's live state,
  Claude Code's settings folder and whether its `settings.json` runs Shepherd's hooks, via
  `ClaudeSetup` in `ReportSource`), and puts a `SourceIntro` per place agents can come from in
  `ModuleContext.sourceGuide`: whether it was found, what it gives and the next step. The
  `sources` module shows them until the first agent appears. Nothing is remembered and no file is
  written; with no config file every source runs with defaults. A source left out of `sources` has no
  card, and the guide is read again when a panel opens while it shows (so installed hooks show).
- `HerdrKit` stays a standalone herdr client: socket, models, `SessionEngine`, transition tracking.
- Gadgets read through a reader target the same way: the module decides when, a separate target
  does the I/O. `OpenUsageSource` implements `UsageReader` (in `ShepherdCore`, with
  `UsageReport`, `UsageProvider`, `UsageMeter`) over OpenUsage's local API (`GET
  http://127.0.0.1:6736/v1/limits`, `openusage.limits.v1`): an ephemeral session, a 2 s timeout,
  no proxy, loopback only (`SHEPHERD_OPENUSAGE_URL` may point at another loopback address).
  Decoding is lenient; `consumption` resources become meters, non-empty `balance` ones notes,
  `errors[]` notes on their provider. Shepherd never reads credentials or calls a vendor API.
  `SystemSource` implements `SystemSampler` (`SystemSample` in `ShepherdCore`) with Mach host
  calls only: CPU as the busy share of `HOST_CPU_LOAD_INFO` ticks since the previous sample,
  memory from `HOST_VM_INFO64` as Activity Monitor's "Memory Used" (internal less purgeable,
  plus wired, plus compressed pages), total from `ProcessInfo.physicalMemory`.
- An agent's own files are read the same way, never as a source: herdr reports each agent's
  `cwd` and `agent_session` (`{"agent":"claude","kind":"id","value":"<session id>"}`), which
  `HerdrSource` passes on as a source-neutral `HerdAgent.session` (`AgentSession`: kind, id,
  cwd). `ClaudeSessionSource` implements `AgentContextReader` for Claude Code: the file is
  `<CLAUDE_CONFIG_DIR or ~/.claude>/projects/<cwd, every non-alphanumeric character as "-">/<id>.jsonl`,
  else a one-time search of `projects/*/<id>.jsonl`. Session ids other than letters, digits,
  "-" and "_" are refused. Off the main actor it reads the last 256 KB, drops the first (cut)
  line, and walks back to the last assistant line that is not a sidechain or a synthetic error
  with `message.usage`; the size is input plus cache read plus cache creation tokens. The same
  walk gives the final message: the `text` blocks of the last main-thread assistant line that has
  any (not "(no content)"), trimmed and cut at 10,000 characters, looked for only in the latest
  turn: a newer prompt, interruption or API error means none (a tool result, a meta entry or a
  local slash command's entries do not end the turn). Both come back as one
  `AgentSessionReading`. Readings are cached by path, size and modification date, so an
  unchanged file costs one `stat`.

### Transition history

`TransitionLog` appends every observed transition to
`~/Library/Application Support/Shepherd/transitions.jsonl`: source, agent id, agent kind,
project label, from, to, time, precision and an opaque source marker. It is written only when
transitions happen, capped by compacting to the newest 5,000 entries, skips unreadable lines, and
never leaves the Mac. It is the history for the timeline, recap and attention ideas, and it lets
time in state survive a restart: herdr's marker is `<terminal id>|<state change seq>`, and when an
agent still has both after a restart, the logged exact time is restored instead of "no later
than". `SHEPHERD_TRANSITION_LOG` points it elsewhere for development runs.

## Layout

| Target | Role |
| --- | --- |
| `HerdrKit` | herdr socket client, lenient Codable models, `SessionEngine`, transition tracking. No UI, no Shepherd. Usable on its own. |
| `HerdrFake` | A fake herdr on a real Unix socket: a scriptable herd or a recorded fixture, with herdr's quirks (one request per connection, subscription validation, both event spellings, `events_lost`). Also the `Sanitiser` for fixtures. Used by tests and later demo mode. No UI. |
| `RecordFixture`, `FakeHerdr` | Dev tools: `make fixture` records a sanitised fixture; `swift run FakeHerdr` runs a fake driven from stdin. |
| `ShepherdCore` | The herd model, `AgentSource`, `HerdStore`, `TransitionLog`, the `ShepherdModule` protocol and `ModuleRegistry`, config (`ConfigStore`, `FileWatcher`), token layouts and the styler, panel values; later the action model. No source types. |
| `HerdrSource` | herdr as a source: adapts `HerdrKit` to the herd model. The only target that sees both. |
| `ReportKit` | The agent report file format, the spool folder (atomic writes, reads, removal), agent identity and the `shepherd-report` command's logic, including `install`/`uninstall claude` (Claude Code's hooks, edited with key order kept). Foundation and CryptoKit only. No UI, no Shepherd. |
| `ReportSource` | Agent reports as a source: watches the spool and maps reports to the herd model through a pure tracker. |
| `TmuxKit` | tmux's command line (`list-panes`, `capture-pane`, `send-keys`, `select-pane`), control mode (`tmux -C`) and the process table (`ps`). Foundation only. No UI, no Shepherd. |
| `TmuxSource` | tmux as a source: panes whose process tree runs a known agent, read from their screens and labelled inferred. A pane's project is its git checkout (or its folder outside git), with the checkout's repo. Watches the socket folder and control clients; no polling. |
| `ShepherdModules` | Built-in features, one folder each, listed in `BuiltinModules.all`. |
| `ShepherdUI` | SwiftUI views, values in, no windows, no glass, so every view can be snapshot tested. Three layers: `Components` (shared pieces: row chrome and the choosable row, the card fill, glyphs, tokens), `Items` (one view per `PanelItem` kind, drawn the same on every surface, with `PanelItemView` the one place a kind meets its view) and `Surfaces` (the panel, the notch, the palette: layout, keyboard and the clock, never their own item views). |
| `Shepherd` | The app: status item, panel window, notch surface window, hotkey, later notifications and the palette. Thin. |

## What herdr gives us

Checked against herdr 0.9.3 (socket protocol 22, `herdr api schema`, the socket API docs, its
source at github.com/herdrdev/herdr, and experiments on a throwaway `herdr --session`).

- **Resources.** `session.snapshot` returns workspaces, tabs, panes, agents and layouts in one
  read, plus `protocol` and `version`. Shepherd checks `protocol` and says clearly when herdr is
  older or newer than it was tested with, instead of failing on a decode.
- **Agent states.** `idle`, `working`, `blocked`, `done`, `unknown`. `done` is not a state of its
  own but "idle and not yet seen", and seen is one flag for the whole server. A pane is seen when
  its tab becomes the active tab of the focused workspace, however that happens: `agent.focus`,
  `workspace.focus`, `tab.focus`, or the user moving around in herdr's own UI. Reading a pane does
  not mark it seen. An agent that finishes in the tab on screen goes straight to `idle` and never
  shows `done`; one in a hidden tab of the focused workspace still does. `blocked` means herdr
  recognised an approval or question UI. `unknown` is not proof of completion.
- **Focus moves everyone.** A successful focus call moves every attached herdr client to the
  target, not one of them. Nothing in herdr brings the terminal app forward; Shepherd does that.
- **Needs you** is Shepherd's term for `blocked` plus `done`. Blocked always ranks first.
- **No timestamps.** The snapshot says what state an agent is in, not since when. herdr keeps one
  change counter for the whole server: when an agent's underlying state (idle, working, blocked,
  unknown) changes, it takes the next value as its `state_change_seq`, and a finished working turn
  also sets `completion_seq` to it. `done` clearing to `idle` changes neither. Shepherd derives
  time in state itself from the transitions it observes, and after a launch or reconnect it shows
  "since Shepherd saw it" rather than inventing a precise time. A higher seq between two snapshots
  means the agent changed even if its state looks the same; because the counter is shared, the
  gap does not say how many times.
- **Tokens** live on workspaces and on panes (`workspace.report_metadata`, `pane.report_metadata`):
  at most 32 keys each, names `[A-Za-z0-9_-]{1,32}`, values up to 80 characters, optional TTL. They
  are not restored after a herdr restart, so an empty token map is normal and never an error.
- **Worktrees.** A workspace inside git carries `worktree { repo_key, repo_name, repo_root,
  checkout_path, is_linked_worktree }`; every checkout of one repo has the same `repo_key`, and
  the main checkout has `is_linked_worktree: false`. A workspace outside git has no `worktree`.
- **Presentation fields.** Pane metadata can override the title, `display_agent` and per-state
  `state_labels`. Shepherd honours them the way herdr's own sidebar does.
- **herdr already alerts.** `ui.toast.delivery` (`off`, `herdr`, `terminal`, `system`; default
  `off`) and `ui.sound.enabled` (default on, with per-agent overrides under `ui.sound.agents`) in
  herdr's config. There is no API to read them, so Shepherd reads `config.toml` as it does for
  token styling. `notification.show` reports `disabled` when delivery is off. Shepherd must not
  double-alert; see "Surfaces".
- **What subscriptions cost herdr.** There is no cap on subscription entries or connections
  (10,000 entries and 300 connections were accepted). The cost is elsewhere: herdr checks every
  `pane.agent_status_changed` entry every 100 ms on its main thread, changes or not. Measured
  herdr CPU: 0.1% with no subscriber, 0.7% with 5 pane entries, 2.1% with 30, 10.6% with 200.
  `pane.output_matched` works the same way. So Shepherd names only agent panes, and never uses
  output matching for a feature that is always on. herdr keeps a 512-event history; a subscriber
  that falls further behind gets `events_lost`.
- **Useful calls beyond the basics:** `agent.read` (up to 1000 lines, 80 by default, read on
  demand; herdr never pushes output changes), `agent.explain` (why herdr chose a state), `agent.prompt` (refuses blocked agents), `agent.send_keys`, `agent.focus`,
  `workspace.focus`, `worktree.create`, `agent.start`, `plugin.action.list` and
  `plugin.action.invoke`.

## Data flow

This is the herdr source. herdr speaks newline-delimited JSON over a Unix socket (`~/.config/herdr/herdr.sock`, or
`HERDR_SOCKET_PATH`, or `sessions/<name>/herdr.sock` for `HERDR_SESSION`). Each request is one line
`{"id","method","params"}`; each response echoes the `id`.

1. **Subscription connection.** One long-lived connection sends `events.subscribe` with every
   workspace, worktree, tab and pane lifecycle type, plus one `pane.agent_status_changed` entry
   per agent pane: herdr requires a `pane_id` for status changes, and lifecycle events alone do not
   report them. Plain shells are left out (each entry costs herdr a check every 100 ms); a shell
   that starts an agent sends the global `pane.agent_detected`, which brings a snapshot and a new
   set. A pane that closes while subscribed does not end the stream: herdr sends `pane_closed`
   and that entry goes quiet. One unknown pane makes herdr reject the whole request (`pane_not_found`) and close
   the connection, so the pane set always comes from the latest snapshot. With nothing open,
   Shepherd starts a global-only subscription (it cannot fail on a pane), then upgrades to the
   full set. When panes change it starts the new subscription before closing the old one, so
   there is no window without events; a rejected upgrade keeps the old one and refreshes. All of
   this lives in `SubscriptionPlanner`, a pure reducer. Wait for `subscription_started`; later
   lines are pushed events. Lifecycle events arrive as `workspace_focused` (underscores, with
   `data.type`), per-pane ones as `pane.agent_status_changed` (dots); Shepherd normalises both.
   There is no general output stream to subscribe to (only `pane.output_matched` for a pattern),
   and that is fine: a surface that shows output (hover peek, the notch pill) reads it on demand
   while visible.
2. **Requests.** herdr serves one request per connection (a second request on the same connection
   gets EOF). Every call connects, writes one line, reads one line and closes, so calls can run in
   parallel and there is no shared request connection to manage.
3. **Events are invalidation, not state.** herdr gives no shared sequence between snapshots and
   events, and orders events only within one subscription entry. Shepherd does not patch its cache
   from event payloads. An event marks state dirty; a coalesced (about 100 ms) `session.snapshot`
   replaces the cache. Refreshes are serialized, and one more runs if events arrive mid-read.
4. **Recovery.** If the subscriber falls behind, herdr sends an error with the subscription's
   request id and `error.code: "events_lost"`, then closes that connection. On that, or on any
   dropped connection: mark state stale, resubscribe, wait for `subscription_started`, take a
   fresh snapshot. If herdr is not running, show a disconnected state, watch the socket's folder
   so a returning herdr is picked up at once, and retry with backoff (0.5 s growing to a 60 s
   cap). Retries faster than once a minute in the first minute after a disconnect are the one
   documented exception to the idle budget. herdr listens as soon as its socket file exists (no
   refused connection was seen in repeated cold starts), but it restores its session after it
   starts listening, so early requests can wait up to 5 s or fail with `server_unavailable`; the
   normal retry covers that.
5. **Transitions.** After each snapshot, `HerdrKit` diffs it against the previous one (status and
   seq fields) and emits transitions with the time Shepherd observed them. Time in state, the
   needs-you queue, notifications and the outcome line all read from these transitions.
6. **Into the herd.** `SessionEngine` publishes immutable `SessionUpdate` values; `HerdrSource`
   adapts each to a `SourceUpdate`, and `HerdStore` (main actor, Swift Observation) sets each
   property only when its value changes, so a surface redraws only when what it shows changed.

## Surfaces

Every surface is optional and degrades on its own.

The menu bar panel and the notch bar have two tabs at the top (`PanelTab`): **Agents**, the
needs-you queue and the project cards, and **Gadgets**, usage, This Mac and future gadgets. Each
section says its tab (`PanelSection.tab`, Agents by default), so a new gadget needs no list. A
surface draws the tab bar, then only the current tab's sections, and its keyboard navigation
covers only those. Each opening starts on Agents; the tab is not saved. ⌘1 and ⌘2 switch tabs
while the surface has the keyboard. With no section off Agents (every gadget turned off, or
hidden by `layout.gadgets`) there is no tab bar. The stage and the "+" live on Agents; switching
away closes a stage. The footer shows on both tabs. Each surface reports its tab to `Presence`,
so a module reads only while its tab shows (`Presence.isShowing(_:)`).

- **Menu bar.** Counts (working, needs you) and a disconnected state. On a MacBook a crowded menu
  bar can hide the item behind the notch, which is one more reason the notch surface exists.
- **Notch surface.** One black shape around the notch, flush with the top of the screen, with
  concave top corners like the hardware notch, so it reads as part of it in either appearance. It
  has three states and morphs between them with a spring (Reduce Motion: the shape changes at once
  and the content crossfades):
  - **Ear**, when nothing is in the pill: a paw sticking out 40 pt to the left of the notch,
    orange with a count when agents need you, dimmed when the state is not live.
  - **Alert**, while a module offers a notch item: the pill below the notch with which agent, why,
    and how many others wait. Click jumps there.
  - **Expanded**, while hovered: the bar. A wide, short shape centred on the notch,
    `min(1000, screen width - 160)` wide and as tall as its content, up to 30% of the screen,
    so it never covers the middle. It reads the same `PanelContentSource` as the menu bar panel
    but lays it out in columns (`BarColumn`): the `queue` section pinned on the left, then one
    column per project or repo card, and any other section as one column, so a new module's section
    just appears as another column. Past the left column the columns scroll sideways; each
    column scrolls on its own past the height cap. Status lines and config problems share one
    line along the bottom. Up and down move within a column, left and right to the nearest row
    of the next column.
  - **Stage**, inside the bar: choosing an agent's row anywhere in the bar (click or Return)
    swaps the project columns for that agent's stage, when its source can read output
    (otherwise it jumps). The arrow on a hovered or selected agent row, ⌘-click and ⌘Return
    skip the stage and jump (`BarChoice`). The
    stage shows the agent's last visible lines (`agent.read`, `source: "visible"`, read once on
    open and again only when the agent's status changes while it is open; nothing while
    closed), the choices `ChoiceParser` finds in them (a run of options numbered from 1 with
    the agent's cursor on one, as Claude Code and Codex draw approval prompts) as buttons with
    their digit, Return and Escape when none parse, and a reply field. A digit or a choice
    sends `agent.send_keys`; a reply sends `pane.send_input` (the text as one bracketed paste,
    then Enter). An agent that is not blocked gets a prompt field instead, sent with
    `agent.prompt` (which herdr refuses for a blocked agent). Escape or Left goes back to the columns; Jump shows the agent in its
    terminal. Typing needs the bar to be key, which a click in the field gives it; while key,
    leaving with the mouse does not fold it. Errors are shown in the stage, never silent.
  - **New task**, a "+" after the project columns when a source can start tasks: a form with
    the project (whose repo the checkout comes from), an agent kind, an optional branch and a
    prompt. Start runs `worktree.create` (`workspace_id`, `branch`, herdr names the branch when
    it is left out), `agent.start` in the new workspace's root pane (a unique name, the kind,
    and `agents.<kind>.args` from config), then `agent.prompt`, and opens the new agent's stage.
    A step that fails after an earlier one worked says what was left behind ("Created worktree
    x, but claude did not start: ...").
- **Usage** (the `usage` module), on the Gadgets tab, a column in the bar and a section in the
  menu bar panel: one card per OpenUsage provider (Claude accounts first), each limit as a thin
  bar (orange from 80%) with its value and "resets in", notes below, dimmed when stale. It reads
  only while a surface shows Gadgets (`Presence.isShowing(.gadgets)`): on showing it when the
  last report is missing or past its earliest future `expiresAt`, then once more at that time if
  still shown; leaving the tab or closing cancels it. Without OpenUsage running the column says so.
- **This Mac** (the `system` module), on the Gadgets tab, a column after usage: one card with CPU
  and memory as bars, in the same gadget card as usage. While Gadgets shows it samples once (which only
  primes the CPU reading), after 0.5 s, then every 2 s; leaving the tab or closing cancels the
  task, so nothing runs otherwise.
- **Context size and final message** (the `context` module, no section of its own): a Claude
  Code agent's context size on its row ("184k", before the time; help "Context: 184,213
  tokens") and in its stage header ("184k context"), and its last message. While a surface shows
  Agents (the palette counts as one) the module reads every agent with a session on showing it,
  then an agent again when its status, its `since` or its session changes, into
  `ModuleContext.agentContext`
  (`AgentContextStore`), which `queue`, `projects` and the palette read into
  `PanelAgentRow.contextTokens` and `finalMessage`. A row shows `messagePreview` under its title,
  one line with whitespace collapsed and `**` and backticks dropped, unless the agent is working
  (the message is then an earlier turn's). Once the agent is idle or done
  (`showsFinalMessage`), the stage and the palette's prompt page show the whole message, inline
  Markdown drawn and selectable, in place of the last lines, and the header row drops its
  preview; a blocked or working agent keeps its lines. Otherwise nothing is read; gone agents
  drop out; turned off, the store empties and rows show neither.
- **Notifications** (the `notifications` module, off by default). When an agent becomes
  `blocked` (a change seen happening, from a live source) while the user is not looking at it
  (`Presence`), it posts through a `Notifier` (the app's is `UNUserNotificationCenter`), one
  notification per agent with Jump and Reply (a reply while blocked, a prompt otherwise), and
  withdraws it once the agent moves on. `"auto"` stays quiet for a source whose
  `SourceUpdate.postsSystemAlerts` is set: herdr's `ui.toast.delivery` "system" or "terminal"
  ("herdr" toasts draw inside herdr's own window). Permission is asked on the first post and
  checked before each one; while it is off in System Settings the footer says so. Confirmed: an
  ad-hoc signed `make app` bundle can ask and post; a Focus mode hides the banners.

  Hovering expands after 120 ms of rest and collapses 300 ms after the mouse leaves; an AppKit
  tracking area on the shape reports it, so nothing wakes while the mouse is elsewhere. Hovering
  never makes the window key, so typing stays in the terminal. A click inside makes it key
  without activating Shepherd (a non-activating `NSPanel` that can become key), then arrows and
  Return work; while it is key, leaving does not collapse it. Escape, a click elsewhere or a jump
  collapses it and hands key back to the app the user was in.

  The SwiftUI view spans a fixed canvas (every state at its largest) that never moves on screen;
  the window is only as large as the current shape. Before a morph the window grows to cover both
  shapes, and once the animation ends it shrinks to the new one. So nothing relies on clicks
  passing through transparent pixels: at rest the only transparent parts are the flared corners.
  On a display without a notch there is no ear and no hover panel; the alert is a small floating
  capsule under the menu bar.
- **Panel.** Click the status item: an `NSPanel` under it with the needs-you queue, then one card
  per project (name, project tokens, each agent with state, time in state and agent tokens), then
  status lines and config problems. It is non-activating but takes key focus, so arrows and
  Return work while the user's terminal stays frontmost. It closes on Escape, an outside click, a
  Space change or after a jump. The window supplies the glass (`NSGlassEffectView`); the SwiftUI
  views carry none. Times tick once a minute only while it is open; closed, it does not exist.
  A right click keeps a small menu (state lines, Quit).
- **"Next" hotkey.** A global hotkey (default ⌃⌥⌘N, configurable, Carbon `RegisterEventHotKey`, no
  permission prompt) jumps to the first waiting agent from a live source that the user is not
  already looking at; repeated presses walk the queue. macOS accepts a combination a system
  shortcut already owns without saying so, so the default avoids known system shortcuts.
- **Notifications.** Only for needs-you and token changes the user asked about, with action
  buttons. On first run Shepherd detects whether herdr's own toasts or sounds are on and asks which
  app should alert, rather than firing both.
- **Palette.** A global hotkey (default ⌥Space, `hotkeys.palette`) opens a search field centred
  in the upper third of the screen under the mouse: a non-activating, key-capable `ShepherdPanel`
  with the glass, like the menu bar panel (`FloatingPanelHost` holds what the two share). It lists
  live agents (as queue rows, with their project), projects and every module's commands, built
  by `PaletteIndex` and ranked by `PaletteSearch` with `FuzzyMatch`: a case- and
  diacritic-insensitive subsequence match that favours word starts, runs and prefixes. Every word
  of the query must match one of an item's words (name, kind, project, status, agent and project
  token values); a name counts most, and its matched characters are bold. With no query, agents
  that need the user come first in queue order. It closes on Escape, an outside click, a Space
  change, losing key or after an action, and is built fresh on every opening. While open it counts
  as a panel showing Agents (so `context` reads), never Gadgets, so gadgets do not start reading
  for it. Tab (or →) on an agent whose
  source can take text opens its prompt page, and the "New task" commands (from `projects`)
  open the new task form; both are a second `StageModel`, so the palette reads an agent's last
  lines only while its prompt shows (on entering and on a status change) and a started task
  turns into the new agent's prompt. Return sends a reply while the agent is blocked and a
  prompt otherwise; a success closes the palette, a failure stays on screen with the text kept.
  Choices are buttons with ⌘ digits, since plain digits are typing. Which keys move between
  pages is a pure `PaletteMode` in Core; Escape goes back to the list, and closes from there.
- **Mac integration** (planned): a Services menu entry to send selected text to an agent, drag and
  drop onto the notch, and App Intents so Spotlight, Shortcuts and Focus filters can drive
  Shepherd.

## Actions

Plugin actions (see "Plugins") are the first kind of user-defined action. One action model feeds every surface. An action has an id, a title, a context (global, workspace,
agent) and a target: a herdr request, a herdr plugin action, or a shell command, with placeholders
such as `{workspace_id}`, `{pane_id}`, `{cwd}`, `{token.pr}`. Modules and config both contribute
actions, and herdr plugin actions are listed automatically through `plugin.action.list`. The panel
cards, the notch, notification buttons, the palette and (later) App Intents all render the same
list, so a new action shows up everywhere without extra code.

## Plugins

Anyone can extend Shepherd with scripts, in any language, without touching Swift. Built-in
features stay modules; a plugin runs outside the app, so a broken one cannot crash Shepherd.
Built-in features use the same extension points where they can (the "ready to land" checks and
questions), so the plugin system is exercised every day.

A plugin is a folder in `~/.config/shepherd/plugins/` (or `SHEPHERD_PLUGINS_PATH`; a symlink
links a local one) with a `shepherd-plugin.json`, decoded leniently like the config. Every plugin
there is on unless its id is in `plugins.disabled`. As built so far: actions, `listActions` and
plugin tokens (`PluginHost` in Core, `ProcessPluginRunner` in the `ShellPlugins` target, the
`plugins` module) and events (`PluginHost` runs them from `HerdStore.events()`); checks and gadgets
are planned (ROADMAP "ready to land").

```json
{
  "id": "ticket-badges",
  "name": "Ticket badges",
  "actions": [
    { "id": "open-pr", "title": "Open PR", "context": "agent", "command": ["./open-pr.sh"] }
  ],
  "listActions": ["./list-actions.sh"],
  "events": [{ "on": ["agent.finished", "agent.blocked"], "command": ["./badge.sh"] }],
  "checks": [{ "title": "Review", "command": ["./review.sh"] }],
  "gadget": { "title": "Deploys", "command": ["./deploys.sh"], "every": 60 }
}
```

- **Actions** have an `id`, a `title`, a `command`, an optional SF Symbol `symbol` and a context:
  `global` (the default), `project` or `agent`. Global actions are palette commands; ⌘K on a
  selected agent or project lists that context's actions. Later also on rows, the stage and the
  ready to land card. `listActions` prints more actions (`{"actions": [...]}`, same shape) at
  runtime, for plugins whose actions are not known in advance; a manifest action with the same
  id wins. A failed listing keeps the last good actions.
- **When plugins run.** Manifests are read and `listActions` run each time the palette opens
  (off the main actor; a refresh already on its way is shared), not watched, so nothing runs at
  idle. Removing a plugin drops its actions and tokens on the next refresh.
- **Events**: `agent.blocked`, `agent.finished`, `agent.started`, `task.started`. A plugin runs
  only for the events it lists, debounced per plugin, agent and event: a repeat within 5 s is
  dropped, and one that arrives during a run runs once more after it. Output is ignored; a failure
  shows under `plugins` in the footer. `task.started` runs in the project's environment with
  `SHEPHERD_AGENT_ID` set to the new agent, which may not be in the herd yet.
- **Checks** add a line to a finished agent's ready to land card. They run when the card shows.
- **Gadgets** print a card for the Gadgets tab. They run only while that tab shows, every `every`
  seconds.

**Running.** A command runs through `/usr/bin/env` (so a bare name is found on `PATH`, with
Homebrew's directories added) from the plugin's folder, off the main actor, with a timeout (30 s
for actions, 10 s for `listActions`, checks and gadgets; then terminated, then killed) and output
capped at 256 KB. A non-zero exit is a failure, shown with the last line of stderr. Shepherd
passes the target as environment variables:

- always `SHEPHERD_PLUGIN_ROOT`;
- for an agent: `SHEPHERD_AGENT_ID` (`herdr:w1:p1`), `SHEPHERD_AGENT_NAME`, `SHEPHERD_AGENT_KIND`,
  `SHEPHERD_AGENT_STATUS`, `SHEPHERD_SESSION_ID`, and its project's variables;
- for a project: `SHEPHERD_PROJECT_ID`, `SHEPHERD_PROJECT_NAME`, `SHEPHERD_PROJECT_PATH` (the
  checkout, from herdr's `worktree`), `SHEPHERD_REPO_NAME`;
- `SHEPHERD_CWD` (the agent's folder, else the project's) and `SHEPHERD_TOKENS` (JSON of what the
  row shows: the source's tokens with the plugins' over them);
- `SHEPHERD_EVENT` (the event's name) for events.

Problems loading or listing go to the panel footer under `plugins`; an action's failure shows on
the palette's result page. Never silent.

**Output.** Plain text is the result: the palette shows an action's text on a result page (no
text closes the palette), a check's first line is its line on the card. A JSON object is applied instead: `{"text": ...}` for the result,
`{"tokens": {"pr": "#12"}}` to set tokens on the target (an empty value removes one), and for a
gadget `{"title": ..., "meters": [...], "lines": [...]}`. Plugin tokens render like a source's
tokens, so they work for every source, not only herdr. They live in memory and go when the plugin
is removed.

**Trust.** A plugin runs the user's own code with the user's permissions; there is no sandbox.
Installing one from elsewhere means reading its manifest first. Nothing runs at idle except the
events a plugin asked for.

**Plugins we ship** in `examples/plugins/`: `herdr-actions` (herdr's plugin actions through
`listActions`; workspace actions become project actions and focus the workspace before
`herdr plugin action invoke`, since herdr acts on its focused workspace), and `diff-stat` (git's
diff stat as the result and `diff_*` tokens).

## Intelligence

v1 has no model. Shepherd does not ship, bundle or require one, and no feature waits on one.

Later, if it earns its place, Apple's on-device model (`FoundationModels`) for very short jobs
only, such as a one-line summary when an agent did not write its own message. It would run on a
transition, only for agents that need you, be off by default, mark its output as generated, and
never trigger an action by itself. Without it, the last meaningful output line is shown.

Local models (Ollama, LM Studio) and a bring-your-own-model endpoint are out. They are slow, take
a lot of memory and disk, and are often poor at this job. Anyone who wants a model can build it as
a plugin.

## Modules

A module is a main-actor class conforming to `ShepherdModule`, in
`Sources/ShepherdModules/<Name>/`. It can contribute any of:

- a menu bar contribution (a glyph or a count),
- a panel section, or a row inside each workspace card,
- notch content (what the pill shows, and when it should appear),
- actions (see "Actions"),
- palette commands (`commands`, a list of `PaletteCommand`: an id, a title, an SF Symbol,
  keywords and a `PaletteAction`). The palette lists every enabled module's commands after the
  agents and projects, so a module adds one by returning it; there is no central list. `queue`
  offers "Next agent that needs you" while a live agent does; `projects` offers "New task…" and
  "New task in <project>" for live projects a task can start in.

Modules receive the herd model (see "Sources"), its transitions and the config through a
`ModuleContext`, plus a `Presence` (whether the agent's host app is frontmost) and actions (jump
to an agent). They do not open their own connections or import source types such as `HerdrKit`.
Contributions are value types (`StatusContribution`, `NotchItem`, `PanelSection`) computed from
observable state; the app reads them inside observation tracking, so a surface redraws only when
what it shows changes. A panel section holds agent rows and project cards, each with its token
lines already styled and the `PanelAction` it performs (jump to an agent, focus a project), or
none when the source cannot. A section names its tab (`PanelSection.tab`); a gadget sets
`.gadgets` and reads only while `Presence.isShowing(.gadgets)`. Built in: `status`, `notch`, `queue` (the needs-you queue, live
sources only), `usage` (plan usage, read through `ModuleContext.usage` only while Gadgets
shows), `system` (CPU and memory, sampled through `ModuleContext.system` only while Gadgets
shows), `context` (context sizes and final messages, read through `ModuleContext.contextReader` only
while Agents or the palette shows), `sources` (the first-run guide: while the herd has no agents, one card per place agents
can come from, from `ModuleContext.sourceGuide`, which the app fills at launch), `notifications` and `projects` (the cards; a source that is not live shows its last known state,
dimmed, never as current; two or more checkouts of one repo, by `HerdProject.repo`, share one
`PanelRepoCard` at the place of the first, main checkout first, each checkout a sub-header
with its agents under it; a checkout with one agent is a single row, its label then the agent's
state, which jumps to the agent).

`ModuleRegistry` builds the enabled modules from `config.modules` (all, in default order, when
absent), reports unknown ids, and rebuilds when the list changes; a module that stays enabled
keeps its instance and state.

### Adding a module

1. Create `Sources/ShepherdModules/<Name>/<Name>Module.swift` conforming to `ShepherdModule`.
2. Add it to `BuiltinModules.all`.
3. Give it an `id`; users enable, disable and order it in config by that id.

A gadget's section becomes a bar column (`BarColumn`), can be turned off in `modules`, and costs
nothing while the bar is closed: it reads or samples only while shown, and never polls in the
background. Everything stays local.

### Adding a gadget

A gadget is a module whose section sets `tab: .gadgets`. Its items are `PanelItem.gadget`
cards (`GadgetCard`: a title, a detail, meters drawn as thin bars, and short lines), which every
surface already draws, so a gadget that fits that shape touches only its module (and its line in
`BuiltinModules.all`). A gadget that needs a look of its own adds one view in
`Sources/ShepherdUI/Items/`, with its value as a `PanelItem` case, one line in `PanelItemView`
and one in `PanelTarget.actions` (what the keyboard can select in it, usually nothing); the
surfaces do not change. Rows reuse `rowChrome` and `choosable` and cards
`card()` from `Components`, so a new view does not copy their padding, highlight or click
handling.

## Config

`~/.config/shepherd/config.json` (or `SHEPHERD_CONFIG_PATH`), plain JSON, reloaded on save.
Every key is optional and a missing file means defaults. As built:

- `modules`: enabled module ids, in order.
- `layout`: what the menu bar panel and the notch bar show, without turning modules off.
  `agents` and `gadgets` list section (module) ids for that tab, in order; a section of that tab
  left out is hidden, and a tab with no list shows all of its sections in `modules` order. A list
  orders only its own tab's sections: an id of a section on the other tab is not moved and is
  reported in the footer. The bar keeps the queue pinned on the left wherever it is listed.
  Hiding every gadget hides the tabs, like turning every gadget off. `projects` lists names,
  matched without regard to case, whose cards come first in that order; a card answers to its
  project's and its repo's names (a repo card also to each checkout's), so a project keeps its
  place when a second checkout makes it a repo card. The rest follow in source order, and a name
  with no project is not an error (projects come and go). An id that names no module is reported
  under `layout`. A hidden gadget's module still runs while its tab shows; leave it out of
  `modules` to stop it.
- `tokens`: `projects` and `agents`, each a list of lines in herdr's sidebar syntax (see "Tokens").
- `hotkeys.next`: the "next" hotkey, `null` to turn it off.
- `hotkeys.palette`: the palette's hotkey (default `option+space`), `null` to turn it
  off. `HotKeyCenter` registers each by name, re-registers on change and reports problems as
  `hotkeys.<name>`, including two hotkeys set to the same combination.

Reading is lenient per key: a key that cannot be used is reported in the panel footer and falls
back to its default while the rest applies; a file that is not valid JSON keeps the last good
config. `FileWatcher` watches the directory (atomic saves) and the file (in-place writes), waits
for a missing directory to appear, debounces 200 ms, and delivers only when the bytes changed.

- `plugins.disabled`: plugin ids to skip (see "Plugins").
- `sources`: the sources `AppController` builds, in herd order; each entry is a source id
  (`herdr`, `report`, `tmux`) or an object with `source` and that source's settings. Left out, all
  three run in that order. The list is read at launch; a changed list is reported in the footer
  as needing a restart. tmux's object takes `agents`: per kind, `process` (default: the kind) and
  `blocked`, `working`, `idle` lists of regular expressions over the screen's last ten non-empty
  lines, trimmed. A state applies when all of its patterns match, blocked before working before
  idle, else unknown; `ChoiceParser` makes any kind blocked. A kind replaces the built-in of that
  name or process; a second kind on one process is reported and skipped. Pattern changes reach
  `TmuxSource.setScreens` on save, which lists the panes again. A bad pattern drops that kind (a
  built-in one keeps its default); an unknown key is only reported.

Planned: `questions` and
`questions.askOnFinish` (see ROADMAP "ready to land"). Once released, config changes
are additive or migrated.

## Tokens

Plugins publish tokens on workspaces and panes; Shepherd shows them with herdr's sidebar rule
semantics exactly: a line of entries, each a token with an optional default `fg`, `bold`, `dim`
and up to 16 rules; the first matching rule wins (`equals`, `contains`, `starts_with`, with ASCII
`ignore_case`, or `gt`/`lt` on a whole finite number), its unset fields inherit, `hide` removes
the token, and missing tokens and empty lines disappear. herdr's built-ins (`state_icon`,
`workspace`, `branch`, ...) are skipped: Shepherd draws those itself.

Which layout applies, per section: Shepherd's config if it defines the section, else the
source's own (for herdr, `ui.sidebar.spaces.rows` for projects and `ui.sidebar.agents.rows` for
agents, read from `HERDR_CONFIG_PATH` or `~/.config/herdr/config.toml` by a small TOML reader and
re-read on change), else every token on one line, sorted, unstyled. A layout replaces, it does
not merge. herdr's colours are picked for dark terminals, so in light mode a colour below 4.5:1
against the panel is darkened until it reads. `rows_by_agent` is not read yet.

## Testing

- **Fixtures** come from a recorder script that sanitises paths, titles and ids as it captures, so
  real data never reaches the repo.
- **Fake herdr** replays fixtures and scripted event streams (including `events_lost` and dropped
  connections) over a real socket, so the client and store are tested end to end.
- **View snapshots**: `ShepherdUI` views render with `ImageRenderer` in light and dark at fixed
  widths with an injected clock, compared with references in `Tests/ShepherdUITests/__Snapshots__`
  (a channel off by more than 8/255 is a different pixel; more than 0.5% fails; actual and diff
  go to `.build/snapshot-failures/`). Anti-aliasing differs between OS builds, so comparison is
  strict only on the build in `RECORDED_ON`; elsewhere, such as CI, views are rendered and uploaded
  as an artifact. `SHEPHERD_RECORD_SNAPSHOTS=1` re-records.
- **Idle budget**: `make perf` (`scripts/perf.sh`) runs the release app against fake herdr, with
  only the herdr source and every path in a temp folder, and fails if CPU over a 30 s idle window
  averages more than 0.5% or the physical footprint is over 60 MB. `PERF_SECONDS`,
  `PERF_CPU_LIMIT` and `PERF_MEMORY_LIMIT_MB` override them. The footprint after opening the bar
  and the palette is still measured by hand. While it runs, a second Shepherd shows its status
  item and notch for about 35 s, with no hotkeys; a running Shepherd is not touched. Leave the
  notch alone while it runs: opening the panel costs CPU and fails the check.
- The UI is still checked by hand against a real herdr before a feature ships (see VISION).

## Performance budget

- Idle: no timers firing faster than once a minute, no polling, and under 0.5% CPU averaged over
  30 s (`make perf`).
- Event bursts coalesced into one snapshot read.
- Only visible surfaces render; the panel tears down its views when closed, and the notch
  surface renders the panel only while expanded (the ear redraws only when the status changes).
- Model calls, output reads and sounds happen on transitions, never on a timer.
- Memory: under 60 MB of physical footprint, what Activity Monitor's Memory column shows, measured
  with `footprint <pid>` on the app after the same steps (idle, then the bar and the palette each
  opened and closed). RSS (`ps -o rss`) is not the budget: it also counts clean pages of shared
  system frameworks, which macOS can drop without cost (against fake herdr, RSS is about 50 MB
  idle and about 77 MB after the palette, footprint about 14 and 24 MB). Panel windows turn
  Writing Tools off in their field editor (`NSText.withoutWritingTools`), because its first focus
  loads a few hundred frameworks.

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

- Clean, small, fast base: near-zero CPU when idle, roughly 40 to 60 MB of memory (a bare AppKit
  status item is about 44 MB).
- Easy to extend: one feature is one module; most customisation is JSON config.
- Correct under load: follows herdr's documented recovery protocol, never shows silently stale
  state.
- Uses what a modern Mac already has (on-device models, speech, Spotlight, Focus) before reaching
  for anything else, and only where it helps the core job.

## Non-goals

- Scraping terminals. Hooks only inside a source adapter, for agents with no API (see "Sources").
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

- Each source declares its **capabilities**: focus, read output, prompt, send keys, approve,
  start an agent, create a worktree. Surfaces hide what a source cannot do instead of failing.
- Each source owns its own connection, recovery and decoding. The "Data flow" rules below are
  herdr's; another source follows the same spirit (no polling where events exist, never show
  stale state as current).
- Hooks are allowed only inside a source adapter, for an agent that has no API. Nothing outside
  the adapter knows a hook exists.
- Order: herdr through public 0.1, then Claude Code directly, then cloud agents through their
  APIs (opt-in, the first network-using sources).

As built:

- `ShepherdCore` holds the herd model (`HerdAgent`, `HerdProject`, `HerdStatus`, `Since`,
  `HerdTransition`, `SourceState`, `SourceCapabilities`), the `AgentSource` protocol and
  `HerdStore`, which merges every source, orders the needs-you queue across them, and routes focus
  to the owning source. Agent and project ids are namespaced by source (`herdr:w1:p1`,
  `herdr:w1`). A project is where agents work (for herdr, a workspace); projects without agents
  are kept, since they are somewhere to go. Project tokens stay on the project and agent tokens
  on the agent.
- `HerdrSource` is the only target that imports both `HerdrKit` and `ShepherdCore`. It adapts
  herdr's session to the herd model, implements focus (`agent.focus`, then the hosting terminal
  forward) and project focus (`workspace.focus`, then the terminal), reports the terminal as its
  host app, and supplies its own status lines (version, protocol warnings, the socket path while
  disconnected, problems in herdr's config). It declares `focus` and `focusProject`. It also
  reads herdr's sidebar config and sends it as the source's token layout (see "Tokens").
- `HerdrKit` stays a standalone herdr client: socket, models, `SessionEngine`, transition tracking.

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
| `ShepherdModules` | Built-in features, one folder each, listed in `BuiltinModules.all`. |
| `ShepherdUI` | SwiftUI views for the panel and the notch surface. Values in, no windows, no glass, so every view can be snapshot tested. |
| `Shepherd` | The app: status item, panel window, notch surface window, hotkey, later notifications and the palette. Thin. |

## What herdr gives us

Checked against herdr 0.9.3 (socket protocol 22, `herdr api schema` and the socket API docs).

- **Resources.** `session.snapshot` returns workspaces, tabs, panes, agents and layouts in one
  read, plus `protocol` and `version`. Shepherd checks `protocol` and says clearly when herdr is
  older or newer than it was tested with, instead of failing on a decode.
- **Agent states.** `idle`, `working`, `blocked`, `done`, `unknown`. `done` means "idle and not
  yet seen". Focusing a pane through the API marks it seen; reading it does not. `blocked` means
  herdr recognised an approval or question UI. `unknown` is not proof of completion.
- **Needs you** is Shepherd's term for `blocked` plus `done`. Blocked always ranks first.
- **No timestamps.** The snapshot says what state an agent is in, not since when. Each agent has
  `state_change_seq` (bumps on every transition) and `completion_seq` (bumps when a working turn
  completes). Shepherd derives time in state itself from the transitions it observes, and after
  a launch or reconnect it shows "since Shepherd saw it" rather than inventing a precise time.
  Comparing seq values between two snapshots reveals transitions that happened in between, even
  when the visible state is the same.
- **Tokens** live on workspaces and on panes (`workspace.report_metadata`, `pane.report_metadata`):
  at most 32 keys each, names `[A-Za-z0-9_-]{1,32}`, values up to 80 characters, optional TTL. They
  are not restored after a herdr restart, so an empty token map is normal and never an error.
- **Presentation fields.** Pane metadata can override the title, `display_agent` and per-state
  `state_labels`. Shepherd honours them the way herdr's own sidebar does.
- **herdr already alerts.** `[ui.toast]` and `[ui.sound]` in herdr's config can notify and play
  sounds. Shepherd must not double-alert; see "Surfaces".
- **Useful calls beyond the basics:** `agent.read` (last lines), `agent.explain` (why herdr chose a
  state), `agent.prompt` (refuses blocked agents), `agent.send_keys`, `agent.focus`,
  `workspace.focus`, `worktree.create`, `agent.start`, `plugin.action.list` and
  `plugin.action.invoke`.

## Data flow

This is the herdr source. herdr speaks newline-delimited JSON over a Unix socket (`~/.config/herdr/herdr.sock`, or
`HERDR_SOCKET_PATH`, or `sessions/<name>/herdr.sock` for `HERDR_SESSION`). Each request is one line
`{"id","method","params"}`; each response echoes the `id`.

1. **Subscription connection.** One long-lived connection sends `events.subscribe` with every
   workspace, worktree, tab and pane lifecycle type, plus one `pane.agent_status_changed` entry
   per pane: herdr requires a `pane_id` for status changes, and lifecycle events alone do not
   report them. One unknown pane makes herdr reject the whole request (`pane_not_found`) and close
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
   documented exception to the idle budget.
5. **Transitions.** After each snapshot, `HerdrKit` diffs it against the previous one (status and
   seq fields) and emits transitions with the time Shepherd observed them. Time in state, the
   needs-you queue, notifications and the outcome line all read from these transitions.
6. **Into the herd.** `SessionEngine` publishes immutable `SessionUpdate` values; `HerdrSource`
   adapts each to a `SourceUpdate`, and `HerdStore` (main actor, Swift Observation) sets each
   property only when its value changes, so a surface redraws only when what it shows changed.

## Surfaces

Every surface is optional and degrades on its own.

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
  - **Expanded**, while hovered: the same panel as under the menu bar item (both read
    `PanelContentSource`), centred on the notch, up to 70% of the screen tall.

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
- **Palette.** A global hotkey opens one fuzzy list for jumping, prompting and running actions.
- **Mac integration** (planned): a Services menu entry to send selected text to an agent, drag and
  drop onto the notch, and App Intents so Spotlight, Shortcuts and Focus filters can drive
  Shepherd.

## Actions

One action model feeds every surface. An action has an id, a title, a context (global, workspace,
agent) and a target: a herdr request, a herdr plugin action, or a shell command, with placeholders
such as `{workspace_id}`, `{pane_id}`, `{cwd}`, `{token.pr}`. Modules and config both contribute
actions, and herdr plugin actions are listed automatically through `plugin.action.list`. The panel
cards, the notch, notification buttons, the palette and (later) App Intents all render the same
list, so a new action shows up everywhere without extra code.

## Intelligence

Optional and local first. It never runs at idle; it runs on a transition and only for agents that
need you.

- **Default: Apple's on-device model** (`FoundationModels`; needs Apple Intelligence turned on). When
  an agent becomes `done` or `blocked`, Shepherd reads its last lines (`agent.read`) and asks for a
  structured result with guided generation: outcome (success, failure, question, unclear), one line
  of summary, and for blocked agents the question and its choices. The text read is not stored.
  On this machine a one-line summary took a few seconds end to end.
- **Fallback:** without the model (Apple Intelligence off or unsupported, an error, a timeout) the
  same place shows the last meaningful output line. Nothing depends on the model being there.
- **Bring your own model** (later): an OpenAI-compatible endpoint in config (a local Ollama or
  LM Studio, or a cloud key) via plain `URLSession`, used only when configured.
- Generated text is marked as generated, can be turned off globally, and never triggers an action
  by itself.

## Modules

A module is a main-actor class conforming to `ShepherdModule`, in
`Sources/ShepherdModules/<Name>/`. It can contribute any of:

- a menu bar contribution (a glyph or a count),
- a panel section, or a row inside each workspace card,
- notch content (what the pill shows, and when it should appear),
- actions (see "Actions").

Modules receive the herd model (see "Sources"), its transitions and the config through a
`ModuleContext`, plus a `Presence` (whether the agent's host app is frontmost) and actions (jump
to an agent). They do not open their own connections or import source types such as `HerdrKit`.
Contributions are value types (`StatusContribution`, `NotchItem`, `PanelSection`) computed from
observable state; the app reads them inside observation tracking, so a surface redraws only when
what it shows changes. A panel section holds agent rows and project cards, each with its token
lines already styled and the `PanelAction` it performs (jump to an agent, focus a project), or
none when the source cannot. Built in: `status`, `notch`, `queue` (the needs-you queue, live
sources only) and `projects` (the cards; a source that is not live shows its last known state,
dimmed, never as current).

`ModuleRegistry` builds the enabled modules from `config.modules` (all, in default order, when
absent), reports unknown ids, and rebuilds when the list changes; a module that stays enabled
keeps its instance and state.

### Adding a module

1. Create `Sources/ShepherdModules/<Name>/<Name>Module.swift` conforming to `ShepherdModule`.
2. Add it to `BuiltinModules.all`.
3. Give it an `id`; users enable, disable and order it in config by that id.

## Config

`~/.config/shepherd/config.json` (or `SHEPHERD_CONFIG_PATH`), plain JSON, reloaded on save.
Every key is optional and a missing file means defaults. As built:

- `modules`: enabled module ids, in order.
- `tokens`: `projects` and `agents`, each a list of lines in herdr's sidebar syntax (see "Tokens").
- `hotkeys.next`: the "next" hotkey, `null` to turn it off.

Reading is lenient per key: a key that cannot be used is reported in the panel footer and falls
back to its default while the rest applies; a file that is not valid JSON keeps the last good
config. `FileWatcher` watches the directory (atomic saves) and the file (in-place writes), waits
for a missing directory to appear, debounces 200 ms, and delivers only when the bytes changed.

Planned: `actions` (see "Actions"), `notifications`, `intelligence`. Once released, config changes
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
- **Idle budget**: a check that runs the app against fake herdr and fails if idle CPU or memory
  exceed the budget.
- The UI is still checked by hand against a real herdr before a feature ships (see VISION).

## Performance budget

- Idle: no timers firing faster than once a minute, no polling.
- Event bursts coalesced into one snapshot read.
- Only visible surfaces render; the panel tears down its views when closed, and the notch
  surface renders the panel only while expanded (the ear redraws only when the status changes).
- Model calls, output reads and sounds happen on transitions, never on a timer.

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

`HerdrKit` stays a standalone herdr client. The herdr source adapts it to the herd model.

## Layout

| Target | Role |
| --- | --- |
| `HerdrKit` | Socket client, lenient Codable models, `SessionStore`, transition tracking. No UI. Usable on its own. |
| `HerdrFake` | Planned. A fake herdr server that replays sanitised fixtures over a real Unix socket. Used by tests and by demo mode. No UI. |
| `ShepherdCore` | `ShepherdModule` protocol, module registry, config loading and reload, token style rules, the action model. |
| `ShepherdModules` | Built-in features, one folder each, listed in `BuiltinModules.all`. |
| `Shepherd` | The app: status item, panel, notch panel, palette, notifications, settings. Thin. |

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

1. **Subscription connection.** One long-lived connection sends `events.subscribe` for the
   workspace, tab, pane lifecycle and `pane.agent_status_changed` events, without pane filters (a
   filter naming a missing pane makes herdr reject the whole request and close the connection).
   Wait for `subscription_started`; later lines are pushed events. There is no general output
   stream to subscribe to (only `pane.output_matched` for a pattern), and that is fine: a surface
   that shows output (hover peek, the notch pill) reads it on demand while visible.
2. **Request connection.** A separate connection for request/response calls.
3. **Events are invalidation, not state.** herdr gives no shared sequence between snapshots and
   events, and orders events only within one subscription entry. Shepherd does not patch its cache
   from event payloads. An event marks state dirty; a coalesced (about 100 ms) `session.snapshot`
   replaces the cache. Refreshes are serialized, and one more runs if events arrive mid-read.
4. **Recovery.** If the subscriber falls behind, herdr sends an error with the subscription's
   request id and `error.code: "events_lost"`, then closes that connection. On that, or on any
   dropped connection: mark state stale, resubscribe, wait for `subscription_started`, take a
   fresh snapshot. If herdr is not running, show a disconnected state and retry with backoff
   (no faster than the idle budget allows once it has been gone a while).
5. **Transitions.** After each snapshot, `HerdrKit` diffs it against the previous one (status and
   seq fields) and emits transitions with the time Shepherd observed them. Time in state, the
   needs-you queue, notifications and the outcome line all read from these transitions.
6. **Observation.** `SessionStore` publishes an immutable `Session` value through Swift
   Observation; views read only the slices they show, so an update redraws only what changed.

## Surfaces

Every surface is optional and degrades on its own.

- **Menu bar.** Counts (working, needs you) and a disconnected state. On a MacBook a crowded menu
  bar can hide the item behind the notch, which is one more reason the notch pill exists.
- **Notch pill** (top-bar fallback without a notch). Appears only when something needs you. Shows
  which agent, why, and its outcome line or last output lines. Click jumps there.
- **Panel.** Workspace cards and the needs-you queue.
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

Modules receive the herd model (see "Sources"), its transitions and the config; they do not open
their own connections or import source types such as `HerdrKit`. The protocol is settled in milestone 1 by building the first two real modules
(menu bar status and notch), not designed ahead of them.

### Adding a module

1. Create `Sources/ShepherdModules/<Name>/<Name>Module.swift` conforming to `ShepherdModule`.
2. Add it to `BuiltinModules.all`.
3. Give it an `id`; users enable, disable and order it in config by that id.

## Config

`~/.config/shepherd/config.json`, reloaded on save. Plain JSON (Foundation only). Planned shape:

- `modules`: enabled module ids, in order.
- `tokens`: per-token styling, using herdr's sidebar rule syntax (`contains`, `starts_with`,
  `equals` mapping to `fg`, `bold`, `dim`, `hide`).
- `actions`: see "Actions".
- `notch`, `hotkey`, `notifications`: on/off and behaviour.
- `intelligence`: on/off, and later an optional model endpoint.

Once released, config changes are additive or migrated.

## Testing

- **Fixtures** come from a recorder script that sanitises paths, titles and ids as it captures, so
  real data never reaches the repo.
- **Fake herdr** replays fixtures and scripted event streams (including `events_lost` and dropped
  connections) over a real socket, so the client and store are tested end to end.
- **View snapshots**: views render with `ImageRenderer` in light and dark at fixed sizes, so a
  reviewer (human or agent) can see a UI change without running the app.
- **Idle budget**: a check that runs the app against fake herdr and fails if idle CPU or memory
  exceed the budget.
- The UI is still checked by hand against a real herdr before a feature ships (see VISION).

## Performance budget

- Idle: no timers firing faster than once a minute, no polling.
- Event bursts coalesced into one snapshot read.
- Only visible surfaces render; the panel and notch tear down their views when hidden.
- Model calls, output reads and sounds happen on transitions, never on a timer.

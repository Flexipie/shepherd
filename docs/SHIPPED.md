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
  terminal forward. Idle: 0% CPU, about 53 MB.
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
  panel closed: 0% CPU over 30 s; open: one wake a minute; about 65 MB, flat over ten opens.
- The notch surface: one black shape around the notch that morphs between a paw ear (orange with
  a count when agents need you), the needs-you pill, and the full panel on hover. Hover never
  takes typing from the terminal; a click inside gives it the keyboard; Escape, a click elsewhere
  or a jump folds it. The window follows the shape, so nothing transparent sits over the menu
  bar at rest. `PanelContentSource` feeds both panels. Idle with the ear showing: 0% CPU over
  30 s, about 62 MB.
- The notch bar: hovering the notch grows a wide, short bar along the top of the screen instead
  of a tall panel. The needs-you queue is pinned on the left, then one column per project
  (`BarColumn`, shared by the view and keyboard navigation), scrolling sideways when there are
  many; arrows move across the grid. The menu bar panel stays vertical. Idle with the ear
  showing: 0% CPU over 30 s, about 54 MB.
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
  bar closed: 0% CPU, about 55 MB, no connections.
- System gadget: a `system` column ("This Mac") after usage with the whole Mac's CPU and memory
  as two bars, from Mach host statistics in the `SystemSource` target. It samples every 2 s only
  while the bar or panel is open; closed, no task and no system calls.

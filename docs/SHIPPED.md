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

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

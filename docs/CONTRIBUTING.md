# Contributing

Thanks for helping. Shepherd is a native macOS app in Swift 6 with no third-party dependencies,
built with SwiftPM (no Xcode project). Read [VISION.md](VISION.md) first: it says who Shepherd is
for and the bar a change has to clear. [PRD.md](PRD.md) says how it is built.

## Before you start

- **A bug:** open an issue with the bug template, or go straight to a PR for a small, clear fix.
- **A feature:** open an issue with the feature template first, so we can agree it fits before you
  build it. Not sure yet? Add it to [IDEAS.md](IDEAS.md) in a PR; nothing there is decided.
- **A security problem:** do not open an issue. See [SECURITY.md](SECURITY.md).

Issues labelled `good first issue` are a good place to start.

## Build and run

You need macOS 26 or later and the Swift 6.2 toolchain (Xcode 26 or its command line tools).
tmux is needed for the tmux source (`brew install tmux`); herdr is optional.

```bash
make build   # swift build
make test    # swift test
make app     # build/Shepherd.app (release, ad-hoc signed)
make demo    # the app on a made-up herd, beside any Shepherd already running
make perf    # idle CPU and memory budget check against a fake herdr
```

`make run` builds the app and relaunches it, quitting any Shepherd already running first. Use
`make demo` or the fake herdr below when you want your own Shepherd left alone.

## Try a change without your real agents

A fake herdr lets you block, finish, add and remove agents and stop herdr without touching real
work. Run it, then type commands into it:

```bash
swift run FakeHerdr /tmp/shepherd-fake.sock
# block w1:p1, done w2:p2, add w3:p1 codex, label w3 docs,
# token w1 pr=#12 draft, token w2:p1 summary=tests pass, stop, start
```

Point a build at it, and away from your own config, history and plugins, with environment
variables:

```bash
make app
HERDR_SOCKET_PATH=/tmp/shepherd-fake.sock \
  SHEPHERD_TRANSITION_LOG=/tmp/shepherd-fake-log.jsonl \
  SHEPHERD_CONFIG_PATH=/tmp/shepherd-config.json \
  SHEPHERD_PLUGINS_PATH=/tmp/shepherd-plugins \
  build/Shepherd.app/Contents/MacOS/Shepherd
```

For the tmux source, use a private server (`tmux -L shepherd-dev`) rather than your own.
`Sources/FakeHerdr/main.swift` lists every fake herdr command.

## Rules

These keep the app small, fast and easy to change. A PR that breaks one will be asked to change.

- No third-party dependencies. Apple frameworks only. Ask in an issue first if you think one is
  needed.
- Swift 6 language mode with strict concurrency. UI on the main actor; I/O off it.
- `HerdrKit` has no UI imports and no knowledge of Shepherd.
- `ShepherdUI` holds SwiftUI views only: values in, no windows, no glass or materials, no
  `Date()` (take `now`).
- Modules see the source-neutral herd model, never `HerdrKit` or other source types.
- A feature is a module under `Sources/ShepherdModules/<Name>/`, registered in
  `BuiltinModules.all`. See "Adding a module" in [PRD.md](PRD.md).
- Decode herdr and agent JSON leniently: ignore unknown fields, tolerate missing optional ones.
- No polling. Subscribe to events and re-read state when told it changed. Idle CPU must stay
  under the budget in [PRD.md](PRD.md), "Performance budget".
- Never commit real data. Test fixtures are sanitised (no real paths, titles or ids); record
  them with `make fixture NAME=<name> SECONDS=10` and read them before committing.
- Keep files small and focused.
- No em dashes in code, comments, docs or commit messages.

## Tests

`make test` runs everything. While working, filter: `swift test --filter TmuxKitTests`.

- Logic goes with a test in the target that owns it. A bug fix comes with a test that fails
  before the fix.
- A new decoder gets a test with unknown and missing fields.
- Anything that writes a user's files gets a test at the edge, including the backup and that only
  Shepherd's own entries change.
- A view gets a snapshot test in `ShepherdUITests`, light and dark.

### View snapshots

Views are rendered and compared with the images in `Tests/ShepherdUITests/__Snapshots__`.
Anti-aliasing differs between macOS builds, so the comparison is strict only on the build named
in `Tests/ShepherdUITests/__Snapshots__/RECORDED_ON`. On any other build (and in CI) the views are
rendered but not compared; CI uploads them as the `view-renders` artifact.

To re-record after changing a view:

```bash
SHEPHERD_RECORD_SNAPSHOTS=1 swift test --filter ShepherdUITests
```

Look at every image that changed before committing it, and say in the PR which changed and why.
If your macOS build is not the one in `RECORDED_ON`, say so: the maintainer re-records on that
build. A failure in a snapshot with a text field is sometimes a few points off under load
([#54](https://github.com/Flexipie/shepherd/issues/54)); run it again on its own before chasing
it.

## Pull requests

- One change per PR. Keep it small; split a big one.
- Title: a plain sentence, with an area prefix when it helps (`tmux: ...`, `Plugins: ...`).
- Body: what it does and why, `Closes #N`, what changed, the tests, the docs touched, and what you
  ran to check it (and what you could not try).
- Update the README and [PRD.md](PRD.md) where behaviour or config changed. Config changes are
  additive.
- CI runs `make build` and `make test` on macOS 26 for every PR.

Commit messages are short and plain: say what changed.

## Code of conduct

Everyone taking part follows the [code of conduct](CODE_OF_CONDUCT.md).

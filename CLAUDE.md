# CLAUDE.md, shepherd

Working notes for agents on this repo. Read this before changing anything; the rest of the
written record is in `docs/`.

## Where to find things

- `README.md` (root): the user-facing tour and build steps.
- `docs/README.md`: the index of every other doc.
- `docs/VISION.md`: **read first.** Shepherd is a real product for every herdr user, published on
  GitHub, not a personal tool. It sets the audience, the principles and the bar a change must
  clear. Creative ideas are welcome: write them in `docs/IDEAS.md`, prototype behind a disabled
  module, and move them to the roadmap only once decided.
- `docs/PRD.md`: what Shepherd is, the architecture, and how to add a module.
- `docs/ROADMAP.md`: OPEN work only. `docs/SHIPPED.md`: what is built, oldest first. When something
  ships, move its entry from the roadmap to the end of SHIPPED.
- The code is the authority on the present. A doc that disagrees with it is stale; fix the doc.

Keep the root to `README.md` and `CLAUDE.md`. A new doc goes under `docs/` and gets a line in
`docs/README.md`.

## What this is

A native macOS menu bar and notch app for running a herd of coding agents, Swift 6 +
SwiftUI/AppKit, built with SwiftPM (no Xcode project). Agents come from sources; herdr's socket API
is the first and, until public 0.1, the only one. Shepherd never scrapes terminals. Hooks, for a
future source with no API, live only inside that source's adapter (`docs/PRD.md`, "Sources").

## Rules

- No third-party dependencies. Apple frameworks only. Ask before adding one.
- Swift 6 language mode with strict concurrency. UI on the main actor; I/O off it.
- `HerdrKit` has no UI imports and no knowledge of Shepherd. It must stay usable on its own.
- `ShepherdUI` holds SwiftUI views only: values in, no windows, no glass or materials (they render
  flat or invisible in `ImageRenderer`), no `Date()` (take `now`). The window supplies the glass.
- Modules see the source-neutral herd model, never `HerdrKit` or other source types.
  `HerdrSource` is the only target that imports both `HerdrKit` and `ShepherdCore`.
- A feature is a module under `Sources/ShepherdModules/<Name>/`, registered in
  `BuiltinModules.all`. Do not grow a central switch or enum of features.
- Decode herdr JSON leniently: ignore unknown fields, tolerate missing optional ones. herdr adds
  fields between releases.
- No polling of herdr. Subscribe to events and treat them as invalidation; re-read state with
  `session.snapshot` (see `docs/PRD.md`, "Data flow").
- Never commit real snapshot data. Test fixtures are sanitised (no real paths, titles or ids).
- Keep files small and focused. Split a view or a client before it passes a few hundred lines.
- Never use em dashes in code, comments, docs or commit messages.

## Commands

```bash
make build   # swift build
make test    # swift test
make app     # build/Shepherd.app (release, ad-hoc signed)
make run     # app, then relaunch it
make fixture NAME=basic SECONDS=10   # record a sanitised fixture from the running herdr
SHEPHERD_LIVE=1 swift test --filter LiveHerdr   # read-only checks against the real herdr
swift run FakeHerdr /tmp/shepherd-fake.sock     # fake herdr driven from stdin (block, done, add,
                                                # label, token, stop, start, focused; see its main.swift)
SHEPHERD_RECORD_SNAPSHOTS=1 swift test --filter ShepherdUITests   # re-record view snapshots
```

Point a dev run at the fake and away from your real files with environment variables:

- `HERDR_SOCKET_PATH=/tmp/shepherd-fake.sock`: the herdr socket.
- `SHEPHERD_TRANSITION_LOG=<path>`: the transition log, so fake runs do not mix into real history.
- `SHEPHERD_CONFIG_PATH=<path>`: Shepherd's config (default `~/.config/shepherd/config.json`).
- `HERDR_CONFIG_PATH=<path>`: herdr's config, read for sidebar token styling.

Snapshot references are compared strictly only on the OS build in
`Tests/ShepherdUITests/__Snapshots__/RECORDED_ON`; after an OS update, re-record and look at the
images before committing them.

Check the UI against the fake before your own herdr: it lets you block, finish, add and remove
agents and stop herdr without touching real work. Review a recorded fixture before committing it.

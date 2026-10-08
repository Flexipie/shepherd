# 🐑 Shepherd

A small native macOS companion for [herdr](https://herdr.dev): a menu bar item and a notch pill
that keep an eye on your herd of coding agents.

Shepherd reads everything from herdr's local socket API. It shows what herdr knows (workspaces,
agents and their state) plus whatever your herdr plugins publish as workspace tokens (a ticket, a
PR number, a diff, a review verdict), and lets you act on it without switching to the terminal.

> Status: early. The live connection, menu bar item and notch pill work; see
> [docs/ROADMAP.md](docs/ROADMAP.md) for what is next.

## What it does today

- **Menu bar item.** A count when agents need you (blocked, or finished and not yet looked at),
  nothing extra when they do not, and a dimmed icon whenever the state is not live. Its menu lists
  who is waiting and for how long; click one to jump there.
- **Notch pill** (a small floating bar on Macs without a notch). A blocked agent stays until it is
  handled; a finished one shows for a few seconds. Nothing shows for the pane you are already
  looking at. Click to focus the pane in herdr and bring your terminal forward.
- **Honest state.** If herdr stops or the event stream breaks, Shepherd says so and recovers on
  its own. Times are "4m" when Shepherd saw the change and "4m+" when it only knows an upper bound.

A tip for MacBooks with a full menu bar: items can hide behind the notch. Cmd-drag the paw icon
somewhere visible; the notch pill works either way.

## Planned

- A panel with one card per workspace: agent state and time in state, plus your plugins' tokens,
  styled with the same rules as herdr's sidebar.
- Native notifications, action buttons defined in config, an on-device one-line summary of what an
  agent did, and a global hotkey.
- Everything is a module, and most behaviour is plain JSON config.

## Requirements

- macOS 26 or later
- herdr 0.9.3 or later, running
- Swift 6.2 toolchain (Xcode 26 or its command line tools) to build

## Build

```bash
make test   # unit tests
make run    # build build/Shepherd.app and launch it
```

To try it without real agents, run a fake herdr and point the app at it:

```bash
swift run FakeHerdr /tmp/shepherd-fake.sock      # then type: block w1:p1, done w2:p2, stop, start
HERDR_SOCKET_PATH=/tmp/shepherd-fake.sock build/Shepherd.app/Contents/MacOS/Shepherd
```

Shepherd has no third-party dependencies.

## Docs

[docs/README.md](docs/README.md) indexes everything else, including the architecture and how to add
a module ([docs/PRD.md](docs/PRD.md)).

## License

MIT

# 🐑 Shepherd

A small native macOS companion for [herdr](https://herdr.dev): a menu bar item and a notch pill
that keep an eye on your herd of coding agents.

Shepherd reads everything from herdr's local socket API. It shows what herdr knows (workspaces,
agents and their state) plus whatever your herdr plugins publish as workspace tokens (a ticket, a
PR number, a diff, a review verdict), and lets you act on it without switching to the terminal.

> Status: early skeleton. See [docs/ROADMAP.md](docs/ROADMAP.md).

## Planned

- Menu bar icon with live counts: agents working, agents that need you.
- A panel with one card per workspace: agent state and how long it has been in it, plus your
  plugins' tokens, styled with the same rules as herdr's sidebar.
- A notch pill (or a small top bar on Macs without a notch) when an agent needs you, with its last
  output lines. Click to jump to that pane.
- Native notifications, action buttons defined in config, and a global hotkey.
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

Shepherd has no third-party dependencies.

## Docs

[docs/README.md](docs/README.md) indexes everything else, including the architecture and how to add
a module ([docs/PRD.md](docs/PRD.md)).

## License

MIT

# 🐑 Shepherd

A small native macOS companion for [herdr](https://herdr.dev): a menu bar item and a notch pill
that keep an eye on your herd of coding agents.

Shepherd reads everything from herdr's local socket API. It shows what herdr knows (workspaces,
agents and their state) plus whatever your herdr plugins publish as workspace tokens (a ticket, a
PR number, a diff, a review verdict), and lets you act on it without switching to the terminal.

> Status: early. The live connection, menu bar item, notch pill, panel and "next" hotkey work;
> see [docs/ROADMAP.md](docs/ROADMAP.md) for what is next.

## What it does today

- **Panel.** Click the paw icon for a panel under it: the needs-you queue on top (blocked first,
  then finished, longest waiting first), then one card per workspace with each agent's state and
  time in state, plus your plugins' tokens. Up and down move the selection, Return jumps, Escape
  or a click outside closes it. Click a card's title to switch herdr to that workspace.
  Right-click the icon for a small menu with the connection state and Quit.
- **"Next" hotkey.** ⌃⌥⌘N from any app jumps to the next agent that needs you; press again to
  walk the queue. Nothing waiting, nothing happens.
- **Notch pill** (a small floating bar on Macs without a notch). A blocked agent stays until it is
  handled; a finished one shows for a few seconds. Nothing shows for the pane you are already
  looking at. Click to focus the pane in herdr and bring your terminal forward.
- **Your herdr colours, no setup.** Token colours and rules come from herdr's own
  `[ui.sidebar]` config, so `$pr`, `$ticket_state` and friends look the way they do in herdr's
  sidebar. Colours picked for dark terminals are darkened in light mode until they read.
- **Honest state.** If herdr stops or the event stream breaks, Shepherd says so, shows the last
  known state dimmed, and recovers on its own. Times are "4m" when Shepherd saw the change and
  "4m+" when it only knows an upper bound.

A tip for MacBooks with a full menu bar: items can hide behind the notch. Cmd-drag the paw icon
somewhere visible; the notch pill and the hotkey work either way.

## Config

Optional. `~/.config/shepherd/config.json` (or `SHEPHERD_CONFIG_PATH`) is read on save; every key
can be left out:

```json
{
  "modules": ["status", "notch", "queue", "projects"],
  "tokens": {
    "projects": [[{ "token": "pr", "fg": "#94e2d5", "rules": [{ "contains": "draft", "dim": true }] }, "ticket_state"]],
    "agents": [["summary"]]
  },
  "hotkeys": { "next": "ctrl+option+cmd+n" }
}
```

- `modules`: which modules run, in order. Panel sections follow this order.
- `tokens`: per section, lines of tokens in herdr's sidebar syntax (`fg`, `bold`, `dim`, and
  `rules` with `equals`, `contains`, `starts_with`, `gt`, `lt`, `ignore_case`, `hide`). A section
  you define replaces herdr's for that section; one you leave out uses herdr's
  (`ui.sidebar.spaces.rows` for projects, `ui.sidebar.agents.rows` for agents), and with neither,
  every token shows unstyled.
- `hotkeys.next`: modifiers (`ctrl`, `option`, `cmd`, `shift`) and one key (a-z, 0-9, `space`,
  `return`, `tab`, `f1`-`f12`); `null` turns it off.

A mistake never breaks the app: the panel footer says what is wrong, and a file that is not valid
JSON keeps the last good config.

## Planned

- Native notifications, action buttons defined in config, and an on-device one-line summary of
  what an agent did.
- A palette for jumping and prompting from anywhere, and Claude Code as a second source.

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
swift run FakeHerdr /tmp/shepherd-fake.sock
# then type: block w1:p1, done w2:p2, add w3:p1 codex, label w3 docs,
#            token w1 pr=#12 draft, token w2:p1 summary=tests pass, stop, start
HERDR_SOCKET_PATH=/tmp/shepherd-fake.sock SHEPHERD_TRANSITION_LOG=/tmp/fake-log.jsonl \
  SHEPHERD_CONFIG_PATH=/tmp/shepherd-config.json build/Shepherd.app/Contents/MacOS/Shepherd
```

Shepherd has no third-party dependencies.

## Docs

[docs/README.md](docs/README.md) indexes everything else, including the architecture and how to add
a module ([docs/PRD.md](docs/PRD.md)).

## License

MIT

# 🐑 Shepherd

A small native macOS companion for [herdr](https://herdr.dev): a menu bar item and a piece of the
notch that keep an eye on your herd of coding agents.

Shepherd reads everything from herdr's local socket API. It shows what herdr knows (workspaces,
agents and their state) plus whatever your herdr plugins publish as workspace tokens (a ticket, a
PR number, a diff, a review verdict), and lets you act on it without switching to the terminal.

> Status: early. The live connection, menu bar item, notch surface, panel and "next" hotkey work;
> see [docs/ROADMAP.md](docs/ROADMAP.md) for what is next.

## What it does today

- **Panel.** Click the paw icon for a panel under it: the needs-you queue on top (blocked first,
  then finished, longest waiting first), then one card per workspace with each agent's state and
  time in state, plus your plugins' tokens. Up and down move the selection, Return jumps, Escape
  or a click outside closes it. Click a card's title to switch herdr to that workspace.
  Right-click the icon for a small menu with the connection state and Quit.
- **"Next" hotkey.** ⌃⌥⌘N from any app jumps to the next agent that needs you; press again to
  walk the queue. Nothing waiting, nothing happens.
- **The notch.** A small paw sticks out to the left of the notch, part of it; it turns orange with
  a count when agents need you. Hover it and a wide, short bar grows out of the notch along the
  top of the screen: the needs-you queue on the left, then one column per project, scrolling
  sideways when there are many. Move away and it folds back. Hovering does not take your typing;
  click inside to use the arrow keys (left and right between columns) and Return, Escape to fold
  it.
- **Answer and prompt from the notch.** Click any agent in the bar to see its last lines right
  there. To skip that and jump straight to the agent, click the arrow on a hovered row, ⌘-click
  the row, or press ⌘Return. For an approval prompt (Claude Code, Codex) its choices are buttons: click one or press
  its digit. Otherwise use Return, Escape, or type a reply. An agent that is idle or finished gets
  a prompt field instead. Escape goes back.
- **New task.** The "+" after the project columns: pick a project, an agent and a prompt
  (a branch name is optional). Shepherd creates a git worktree from that project's repo, starts
  the agent in it and sends the prompt, then shows you the new agent.
- **Usage.** A column next to the needs-you list shows your Claude Code plan limits (session,
  weekly, per model, extra usage) for every account, plus Codex and anything else you track, with
  when each resets. It reads them from [OpenUsage](https://github.com/robinebers/openusage), which
  must be running: Shepherd asks its local API on `127.0.0.1:6736` and nothing else, holds no
  credentials and sends nothing anywhere. It reads only while the bar or panel is open, at most
  once per OpenUsage refresh. Without OpenUsage the column says so. Turn it off by leaving `usage`
  out of `modules`.
- **This Mac.** A small column after usage shows the whole Mac's CPU and memory as two bars
  (memory as Activity Monitor's "Memory Used"). It samples every 2 seconds only while the bar or
  panel is open; closed, nothing runs. Turn it off by leaving `system` out of `modules`.
- **Notch pill** (a small floating bar on Macs without a notch). A blocked agent stays until it is
  handled; a finished one shows for a few seconds. Nothing shows for the pane you are already
  looking at. Click to focus the pane in herdr and bring your terminal forward.
- **Your herdr colours, no setup.** Token colours and rules come from herdr's own
  `[ui.sidebar]` config, so `$pr`, `$ticket_state` and friends look the way they do in herdr's
  sidebar. Colours picked for dark terminals are darkened in light mode until they read.
- **Honest state.** If herdr stops or the event stream breaks, Shepherd says so, shows the last
  known state dimmed, and recovers on its own. Times are "4m" when Shepherd saw the change and
  "4m+" when it only knows an upper bound.

A tip for MacBooks with a full menu bar: items can hide behind the notch. The notch bar and the
hotkey work either way; to see the menu bar icon too, Cmd-drag it somewhere visible.

## Config

Optional. `~/.config/shepherd/config.json` (or `SHEPHERD_CONFIG_PATH`) is read on save; every key
can be left out:

```json
{
  "modules": ["status", "notch", "queue", "usage", "system", "projects"],
  "tokens": {
    "projects": [[{ "token": "pr", "fg": "#94e2d5", "rules": [{ "contains": "draft", "dim": true }] }, "ticket_state"]],
    "agents": [["summary"]]
  },
  "hotkeys": { "next": "ctrl+option+cmd+n" },
  "agents": { "claude": { "args": [] } },
  "notifications": "off"
}
```

- `modules`: which modules run, in order. Panel sections follow this order; in the notch bar the
  queue stays on the left and the others follow as columns.
- `tokens`: per section, lines of tokens in herdr's sidebar syntax (`fg`, `bold`, `dim`, and
  `rules` with `equals`, `contains`, `starts_with`, `gt`, `lt`, `ignore_case`, `hide`). A section
  you define replaces herdr's for that section; one you leave out uses herdr's
  (`ui.sidebar.spaces.rows` for projects, `ui.sidebar.agents.rows` for agents), and with neither,
  every token shows unstyled.
- `hotkeys.next`: modifiers (`ctrl`, `option`, `cmd`, `shift`) and one key (a-z, 0-9, `space`,
  `return`, `tab`, `f1`-`f12`); `null` turns it off.
- `agents.<kind>.args`: extra arguments when a new task starts that agent, for example
  `"claude": { "args": ["--dangerously-skip-permissions"] }`. That flag lets Claude Code run every
  tool and command without asking you first, so nothing will block for approval; use it only
  where that is safe (a worktree you can throw away, a machine without secrets). Off unless you set
  it.
- `notifications`: macOS notifications when an agent blocks while you are not looking at it, with
  Jump and Reply buttons. `"off"` (the default; the notch is the alert), `"on"`, or `"auto"`
  (on unless herdr already posts system notifications itself, `ui.toast.delivery` "system" or
  "terminal"). macOS asks for permission the first time; if it is off in System Settings, the
  bar's footer says so.

A mistake never breaks the app: the panel footer says what is wrong, and a file that is not valid
JSON keeps the last good config.

## Planned

- Action buttons defined in config, and an on-device one-line summary of
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

## Thanks

The usage column reads from [OpenUsage](https://github.com/robinebers/openusage) by Robin Ebers
(MIT), which does the hard part of finding and refreshing each account.

## License

MIT

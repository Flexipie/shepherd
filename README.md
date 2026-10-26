# 🐑 Shepherd

A small native macOS companion for [herdr](https://herdr.dev): a menu bar item and a piece of the
notch that keep an eye on your herd of coding agents.

Shepherd reads everything from herdr's local socket API. It shows what herdr knows (workspaces,
agents and their state) plus whatever your herdr plugins publish as workspace tokens (a ticket, a
PR number, a diff, a review verdict), and lets you act on it without switching to the terminal.

> Status: early. The live connection, menu bar item, notch surface, panel, palette and "next"
> hotkey work;
> see the [issues](https://github.com/Flexipie/shepherd/issues) and
> [docs/ROADMAP.md](docs/ROADMAP.md) for what is next.

## What it does today

- **Panel.** Click the paw icon for a panel under it: the needs-you queue on top (blocked first,
  then finished, longest waiting first), then one card per workspace with each agent's state and
  time in state, plus your plugins' tokens. Up and down move the selection, Return jumps, Escape
  or a click outside closes it. Click a card's title to switch herdr to that workspace.
  Worktrees of one repo share a card (and a column in the notch bar): the repo's name on top,
  then the main checkout and each worktree with its own label, tokens and agents (one row when
  it has one agent). Click a worktree's line to switch herdr to it, and type the repo's name in the palette to find them
  all.
- **Agents | Gadgets.** The panel and the notch bar have two tabs at the top: Agents (the queue
  and your projects, where each opening starts) and Gadgets (usage, This Mac). Click a tab or
  press ⌘1 and ⌘2. With every gadget turned off there are no tabs. A gadget reads only while
  its tab shows.
  Right-click the icon for a small menu with the connection state and Quit.
- **"Next" hotkey.** ⌃⌥⌘N from any app jumps to the next agent that needs you; press again to
  walk the queue. Nothing waiting, nothing happens.
- **Palette.** ⌥Space from any app opens a search box in the middle of the screen. Type part of
  an agent, a workspace, a status or any token value (a PR number, a ticket) to find it; up and
  down move, Return jumps (or switches herdr to the workspace), Escape closes. With nothing typed
  it lists the agents that need you first. Commands such as "Next agent that needs you" are in
  the same list. Your terminal stays frontmost the whole time.
- **Prompt from the palette.** Tab (or →) on an agent turns the search field into a prompt for it,
  with its last lines underneath. Type and press Return: a prompt for an idle or finished agent,
  a reply for one that needs you. An approval prompt's choices are buttons, ⌘1, ⌘2 and so on.
  Escape (or ← in an empty field) goes back to the list with your search kept. "New task…" and
  "New task in <project>" open the new task form right there, and the palette then shows the new
  agent.
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
- **Usage.** On the Gadgets tab, a column shows your Claude Code plan limits (session,
  weekly, per model, extra usage) for every account, plus Codex and anything else you track, with
  when each resets. It reads them from [OpenUsage](https://github.com/robinebers/openusage), which
  must be running: Shepherd asks its local API on `127.0.0.1:6736` and nothing else, holds no
  credentials and sends nothing anywhere. It reads only while the Gadgets tab shows, at most
  once per OpenUsage refresh. Without OpenUsage the column says so. Turn it off by leaving `usage`
  out of `modules`.
- **This Mac.** A small column after usage shows the whole Mac's CPU and memory as two bars
  (memory as Activity Monitor's "Memory Used"). It samples every 2 seconds only while the
  Gadgets tab shows; otherwise nothing runs. Turn it off by leaving `system` out of `modules`.
- **Context size.** A Claude Code agent's row and stage show how full its context is ("184k",
  the last turn's input and cache tokens). Shepherd finds the session herdr reports for the pane
  and reads only the tail of its file under `~/.claude/projects` (or `CLAUDE_CONFIG_DIR`),
  read-only, when the Agents tab shows and when that agent's state changes; otherwise nothing
  is read. Other agents show none for now. Turn it off by leaving `context` out of `modules`.
- **Notch pill** (a small floating bar on Macs without a notch). A blocked agent stays until it is
  handled; a finished one shows for a few seconds. Nothing shows for the pane you are already
  looking at. Click to focus the pane in herdr and bring your terminal forward.
- **Your herdr colours, no setup.** Token colours and rules come from herdr's own
  `[ui.sidebar]` config, so `$pr`, `$ticket_state` and friends look the way they do in herdr's
  sidebar. Colours picked for dark terminals are darkened in light mode until they read.
- **First run.** No config file needed. Until an agent shows, the panel starts with where agents
  can come from (tmux, Claude Code, herdr), what Shepherd found of each and what to do next.
  Without herdr nothing says "not connected".
- **Honest state.** If herdr's connection or event stream breaks, Shepherd says so, shows the last
  known state dimmed, and recovers on its own. When herdr quits, its agents go until it starts again. Times are "4m" when Shepherd saw the change and
  "4m+" when it only knows an upper bound.

A tip for MacBooks with a full menu bar: items can hide behind the notch. The notch bar and the
hotkey work either way; to see the menu bar icon too, Cmd-drag it somewhere visible.

## Plugins

Add your own actions with a script in any language. A plugin is a folder in
`~/.config/shepherd/plugins/` with a `shepherd-plugin.json`:

```json
{
  "id": "open-pr",
  "actions": [{ "id": "open", "title": "Open the PR", "context": "project", "command": ["sh", "open.sh"] }]
}
```

Global actions show up in the palette; ⌘K on an agent or a project lists its own. The script
gets the target as environment variables (`SHEPHERD_CWD`, `SHEPHERD_PROJECT_PATH`,
`SHEPHERD_AGENT_ID`, `SHEPHERD_TOKENS` and more) and can print text, which the palette shows, or
JSON such as `{"tokens": {"pr": "#12"}}`, which sets tokens on that row for any agent, herdr or
not. Plugins run your own code with your permissions, so only add ones you have read. Nothing
runs until you open the palette. See `examples/plugins/` (every herdr plugin action in the
palette, and a diff stat) and "Plugins" in `docs/PRD.md`.

## Config

Optional. `~/.config/shepherd/config.json` (or `SHEPHERD_CONFIG_PATH`) is read on save; every key
can be left out:

```json
{
  "modules": ["status", "notch", "sources", "queue", "usage", "system", "projects", "context"],
  "tokens": {
    "projects": [[{ "token": "pr", "fg": "#94e2d5", "rules": [{ "contains": "draft", "dim": true }] }, "ticket_state"]],
    "agents": [["summary"]]
  },
  "hotkeys": { "next": "ctrl+option+cmd+n", "palette": "option+space" },
  "agents": { "claude": { "args": [] } },
  "notifications": "off",
  "plugins": { "disabled": [] },
  "sources": ["herdr", "report", "tmux"],
  "layout": { "agents": ["queue", "projects"], "gadgets": ["system", "usage"], "projects": ["api"] }
}
```

- `modules`: which modules run, in order. Panel sections follow this order; in the notch bar the
  queue stays on the left and the others follow as columns.
- `layout`: choose and order what the panel and the bar show, without turning modules off.
  `agents` and `gadgets` list the sections of that tab in order (`queue`, `projects`, `usage`,
  `system`); one you leave out is hidden. `projects` names the project or repo columns to show
  first, in that order; the rest follow. Left out, everything shows as it does today.
- `tokens`: per section, lines of tokens in herdr's sidebar syntax (`fg`, `bold`, `dim`, and
  `rules` with `equals`, `contains`, `starts_with`, `gt`, `lt`, `ignore_case`, `hide`). A section
  you define replaces herdr's for that section; one you leave out uses herdr's
  (`ui.sidebar.spaces.rows` for projects, `ui.sidebar.agents.rows` for agents), and with neither,
  every token shows unstyled.
- `hotkeys.next` and `hotkeys.palette`: modifiers (`ctrl`, `option`, `cmd`, `shift`) and one key
  (a-z, 0-9, `space`, `return`, `tab`, `f1`-`f12`); `null` turns one off. macOS does not say when
  a system shortcut or another app (Raycast and Alfred like ⌥Space too) already owns a
  combination, so if the palette does not open, pick another (`ctrl+option+space`, for example).
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

- `plugins.disabled`: plugin ids to leave off. Every plugin in the plugins folder is on otherwise.
- `sources`: where agents come from, in the order they are listed: `herdr`, `report`
  (`shepherd report`) and `tmux`. Left out, all three run. A change to the list applies the next
  time Shepherd starts. tmux can be an object instead, to teach it an agent or change how it reads
  one:

  ```json
  { "source": "tmux", "agents": {
      "aider": { "process": "aider", "working": ["Thinking"], "idle": ["(?m)^>$"] } } }
  ```

  A pane is that agent when a process under its shell has the `process` name (by default the kind
  itself). `blocked`, `working` and `idle` are lists of regular expressions, matched against the
  last ten non-empty lines of the screen, each line trimmed; a state applies when every pattern in
  its list is found, checked in that order. A numbered prompt (`1. Yes`) is blocked for any agent.
  A kind replaces the built-in one of the same name or process (`claude`, `codex`); two of your
  kinds on one process are reported. Pattern changes apply on save.

A mistake never breaks the app: the panel footer says what is wrong, and a file that is not valid
JSON keeps the last good config.

## Planned

- Any terminal agent: tmux and agent reports, so herdr is no longer required (see the "Any terminal
  agent" milestone).
- Action buttons defined in config.
- A UI and UX pass, columns and gadgets you choose and order in config, and Claude Code as a
  second source.

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

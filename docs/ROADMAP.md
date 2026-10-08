# Roadmap

Open work only. When something ships, move it to the end of [SHIPPED.md](SHIPPED.md).

Each milestone ends with something usable and a "done when" check. Ideas that are not decided
stay in [IDEAS.md](IDEAS.md).

## Milestone 0: foundations

- CI on GitHub Actions (macOS runner): `make build` and `make test` on every push and PR.
- Fixture recorder script: captures `session.snapshot` and a stretch of the event stream, and
  rewrites paths, titles and ids as it goes, so fixtures are sanitised by construction.
- `HerdrFake`: a fake herdr that serves fixtures and scripted event streams (including
  `events_lost` and dropped connections) over a real Unix socket.

Done when: CI is green and a test talks to `HerdrFake` over a socket.

## Milestone 1: live connection, menu bar and notch base

- `HerdrKit` client: request and subscription connections, lenient models for the snapshot
  (workspaces, tabs, panes, agents, workspace and pane tokens, presentation fields) and the events
  Shepherd uses, and a protocol and version check.
- `SessionStore`: invalidate, coalesce, serialized refresh, `events_lost` and reconnect handling
  as in PRD "Data flow", and a disconnected state.
- Transition tracking: diff snapshots (status, `state_change_seq`, `completion_seq`), record when
  Shepherd observed each change, derive time in state.
- Settle the `ShepherdModule` protocol by building the first two modules below.
- Status item with live counts (working, needs you), disconnected state when herdr is not running.
- Notch panel base: appears when an agent needs you, shows which one, click focuses its pane
  (which marks it seen) and brings the terminal forward. Top-bar fallback without a notch.

Done when: against a real herdr, a blocked agent shows in the notch within a second, clicking
jumps to it, and quitting and restarting herdr shows disconnected and then recovers.

## Milestone 2: the panel

- Workspace cards: label, each agent's state and time in state (honouring `display_agent` and
  `state_labels`), workspace and pane tokens styled by config rules.
- Needs-you queue at the top: blocked first, then unseen done, oldest first, one key to jump
  through them in order.
- Focus button (`agent.focus` or `workspace.focus`, plus activating the terminal app across
  Spaces and displays).
- Config file with hot reload: modules, token styles.
- View snapshot tests (`ImageRenderer`, light and dark) for cards and the queue.

Done when: someone running five agents can answer "who needs me, and for how long" from the
panel without opening the terminal.

## Milestone 3: alerts that earn it

- Native notifications for needs-you and configured token changes, with Jump and Reply buttons.
- First-run alert choice: detect herdr's own toasts and sounds and let the user pick which app
  alerts, so nothing fires twice.
- Outcome line: on `done` or `blocked`, the on-device model (`FoundationModels`)
  produces a structured one-line result for the notch and notifications; the last output line is
  the fallback everywhere else.
- The action model from PRD "Actions": config actions with placeholders, and herdr plugin
  actions listed automatically, shown on cards, in the notch and as notification buttons.
- Notch pill shows the agent's last output lines.

Done when: with herdr's own alerts off, a day of real use produces no notification the user did
not want, and every one of them can be acted on without switching apps.

## Milestone 4: public 0.1

- Signed and notarised build and a DMG from a GitHub Actions release workflow; a Homebrew cask.
- First run: detects herdr, explains what it found, works with no config file.
- Demo mode: a built-in fake herd (from `HerdrFake`) so people can try Shepherd without herdr,
  and so the README GIF is reproducible.
- README that sells it in one screen: GIF, pitch, one-command install, the privacy statement.
- Idle budget check (`make perf`): fails if idle CPU or memory exceed the PRD budget.
- Tagged release with a changelog.

Done when: a stranger installs it from the README in a minute and it works with their herd.

## Milestone 5: from anywhere

- Palette: a global hotkey opens one fuzzy list (by workspace, agent, token) to jump, prompt an
  agent (`agent.prompt`) or run any action.
- New task: from the palette, pick a repo, type a prompt; Shepherd creates a worktree, starts an
  agent and sends the prompt (`worktree.create`, `agent.start`, `agent.prompt`).
- Drop onto the notch: drag a file, screenshot or URL onto an agent to send it as a prompt.
- Services menu: "Send to agent" for selected text in any app.
- Spike: App Intents for Spotlight and Shortcuts under the SwiftPM build. Ship them if the build
  works without an Xcode project; otherwise write down why and park it.

## Later

- Settings window.
- Mascot with idle animations, sounds you can replace, weekly recap.

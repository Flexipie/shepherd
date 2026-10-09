# Roadmap

Open work only. When something ships, move it to the end of [SHIPPED.md](SHIPPED.md).

Each milestone ends with something usable and a "done when" check. Ideas that are not decided
stay in [IDEAS.md](IDEAS.md).

## To confirm against a real herdr

Found while building milestone 1 and not yet checked, because each needs changes to a live
session. Confirm, then record the answer in PRD "What herdr gives us" or "Data flow".

- Does closing a subscribed pane end the whole subscription? If so, treat an EOF within about a
  second of `pane_closed` as a routine resubscribe, without flashing "stale".
- Does `agent.focus` bump `state_change_seq`?
- Is there a limit on subscription entries (try 200+ panes)?
- Does herdr create its socket file before it listens? If so, retry `ECONNREFUSED` once after
  250 ms instead of waiting for the backoff.
- When the user looks at a finished pane in herdr's own UI, does the API's `done` clear, or only
  after `agent.focus`? herdr tracks "seen" per client, so the menu bar count could lag.
- Clicking the pill or a menu entry: herdr focuses the pane and the terminal comes forward. The
  `agent.focus` request is tested against the fake; the click and the terminal activation have
  not been tried on a real blocked agent yet.
- The floating fallback bar on a display without a notch, and the pill on a second display.

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
- The sheepdog: a mascot that sleeps when the herd is idle, perks up while agents work and herds
  the ones that need you toward the notch. Light at idle, honours Reduce Motion, can be turned
  off. It is the README GIF.
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

## Milestone 6: a second source

- Claude Code as a source without herdr, through its hooks, contained in its own adapter (PRD
  "Sources"). Capabilities it cannot offer are hidden, not faked.
- First run detects which sources are present and explains each.
- Demo mode covers both sources.

Done when: someone who has never installed herdr runs three Claude Code sessions and works their
needs-you queue from Shepherd.

## Later

- Settings window.
- Cloud agent sources through their APIs (opt-in, network use stated plainly).
- Sounds you can replace, weekly recap.

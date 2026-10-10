# Roadmap

Open work only. When something ships, move it to the end of [SHIPPED.md](SHIPPED.md).

Each milestone ends with something usable and a "done when" check. Ideas that are not decided
stay in [IDEAS.md](IDEAS.md).

## To check by hand

herdr's own behaviour is confirmed and recorded in PRD "What herdr gives us" and "Data flow".
These need a person, real agents or other hardware:

- Clicking the pill or a menu entry: herdr focuses the pane and the terminal comes forward. The
  `agent.focus` request is tested against the fake; the click and the terminal activation have
  not been tried on a real blocked agent yet.
- The floating fallback bar on a display without a notch, and the pill on a second display.
- Found in milestone 2: clicking a project card (`workspace.focus`) and a blocked agent in the
  panel on a real herdr; closing the panel with a real click outside it; token colours and rules
  matching herdr's own sidebar side by side; VoiceOver reading the panel rows.

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

## Follow-ups from milestone 2

- Ask herdr upstream for a global, event-driven agent status subscription (no `pane_id`).
  Today each subscribed pane costs herdr a check every 100 ms (PRD "What subscriptions cost
  herdr"); with a global event Shepherd's cost inside herdr would be near zero.

- `rows_by_agent` from herdr's sidebar config (per agent kind layouts).
- Memory: about 65 MB with the notch pill showing, above the 40 to 60 MB budget. Measure what the
  panel's first open costs and what stays resident.

## Later

- Settings window.
- Cloud agent sources through their APIs (opt-in, network use stated plainly).
- Sounds you can replace, weekly recap.

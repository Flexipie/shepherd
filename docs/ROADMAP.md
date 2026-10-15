# Roadmap

Open work only. When something ships, move it to the end of [SHIPPED.md](SHIPPED.md).

Milestones are in the order they will be worked on; each ends with something usable and a
"done when" check. Ideas that are not decided stay in [IDEAS.md](IDEAS.md).

## To check by hand

herdr's own behaviour is confirmed and recorded in PRD "What herdr gives us" and "Data flow".
These need a person, real agents or other hardware:

- The floating fallback bar on a display without a notch, and the pill on a second display.
- From milestone 2: clicking a project card (`workspace.focus`) and a blocked agent on a real
  herdr; closing the panel with a real click outside it; token colours and rules matching herdr's
  own sidebar side by side; VoiceOver reading the panel rows.
- From the notch bar work: answering a real Claude Code and Codex approval prompt from the stage
  (digit and button); prompting a real idle agent; a new task on a real herdr (creates a git
  worktree); left and right keys scrolling across columns in the live bar; Reply from a macOS
  notification with no Focus mode on.
- From the palette: Escape handing typing back to the previous app; Tab, →, ← and ⌘ digits in the
  fields; prompting a real idle agent and answering a real approval; a new task from it on a real
  herdr; whether ⌥Space clashes with a launcher such as Raycast or Alfred; a config change
  re-registering the hotkey live, and a clash with `hotkeys.next` showing in the footer.

## Milestone 5: UI and UX pass, and a modular UI

Done before any new gadget.

- The user's list from daily use: the bar and stage (column widths and height cap, what the ear
  and pill show, keyboard and mouse rough edges), the panel and the palette.
- A modular UI in code: shared row and card components and a clear surface layer, so a new
  surface or gadget does not copy views.
- A modular UI for the user: choose and order columns and gadgets from config, later a settings
  window.

Done when: the user's list is done, and adding a gadget touches only its module and one view.

## Milestone 6: more from anywhere

- Drop onto the notch: drag a file, screenshot or URL onto an agent to send it as a prompt.
- Services menu: "Send to agent" for selected text in any app.
- Spike: App Intents for Spotlight and Shortcuts under the SwiftPM build. Ship them if the build
  works without an Xcode project; otherwise write down why and park it.

## More gadgets

After milestone 5. Each gadget is a module whose section becomes a bar column (`BarColumn`), can
be turned off in `modules`, and costs nothing while the bar is closed: it reads or samples only
while shown, and never polls in the background. Everything stays local.

## Milestone 7: a second source

- Claude Code as a source without herdr, through its hooks, contained in its own adapter (PRD
  "Sources"). Capabilities it cannot offer are hidden, not faked.
- First run detects which sources are present and explains each.
- Demo mode covers both sources.

Done when: someone who has never installed herdr runs three Claude Code sessions and works their
needs-you queue from Shepherd.

## Follow-ups

- Ask herdr upstream for a global, event-driven agent status subscription (no `pane_id`).
  Today each subscribed pane costs herdr a check every 100 ms (PRD "What subscriptions cost
  herdr"); with a global event Shepherd's cost inside herdr would be near zero.
- `rows_by_agent` from herdr's sidebar config (per agent kind layouts).
- Snapshots with a text field sometimes render it a few points off under load (CI on
  `notch-stage-context`, locally on a palette snapshot during a full run); reruns pass. Find what
  moves it, or keep text fields out of compared snapshots.
- Memory: 54 to 65 MB, at or above the 40 to 60 MB budget. Measure what the bar's first open
  costs and what stays resident. The palette's first open adds about 45 MB (56 to 101 MB) that
  stays resident.

## Public 0.1 (later)

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

Not started until the user decides to publish.

Done when: a stranger installs it from the README in a minute and it works with their herd.

## Later

- Settings window.
- Cloud agent sources through their APIs (opt-in, network use stated plainly).
- Sounds you can replace, weekly recap.

# Ideas

An open idea bank. Nothing here is decided. Add freely; when an idea is chosen, move it to
[ROADMAP.md](ROADMAP.md). See [VISION.md](VISION.md) for what makes an idea a good fit.

Format: a short title, what it is, and why a user would care. Note the herdr API it needs when you
know it.

## Attention

- **Quiet hours and focus mode.** Hold notifications while you are in a meeting or focus mode,
  then show a digest. Best done as a Focus filter (see "Mac integration") so it follows the
  system Focus the user already uses.
- **Escalation.** A blocked agent nobody answered for N minutes gets louder (sound, menu bar
  colour), configurable.
- **Stuck detection.** An agent "working" with no output change for a long time is flagged as
  possibly stuck (`pane.output_matched`, output revisions).
- **Welcome-back digest.** When you unlock the Mac or return from idle, one small summary of what
  finished and what is blocked while you were away, instead of a pile of notifications. Uses
  `NSWorkspace` session notifications plus the current snapshot.
- **Why is it blocked?** A button on a blocked or `unknown` agent that shows herdr's own reasoning
  (`agent.explain`) and the last lines (`agent.read`), so you can decide without switching apps.
- **Quick wins first.** Order the needs-you queue so yes/no approvals come before open-ended
  questions, using the outcome classification. Clear five small blockers in a minute, then think.
- **Away mode.** When the Mac has been locked for N minutes, forward needs-you to your phone
  through a user-configured action (for example a self-hosted ntfy topic or a Pushover webhook).
  Nothing leaves the Mac unless the user sets it up.
- **Fewer interruptions at the source.** Shepherd sees every approval. When the same one keeps
  coming back ("you approved `swift test` 14 times this week"), it suggests adding it to that
  agent's allowlist, with the exact config line. Calm by design: fewer interruptions, not just
  better ones.
- **Attention budget.** "Minutes agents waited on you" as the one number a user watches (and the
  product's north star). When answer times keep climbing, gently suggest running fewer agents at
  once. Shown in the panel and recap, never as a notification.

## Awareness

- **Live activity line.** What each agent is doing right now (reading a file, running tests),
  when a plugin or agent hook reports it as a pane token.
- **Change summary.** Per workspace: diff size, files touched, and a sparkline of activity over
  the last hour.
- **Herd overview.** A compact grid of all agents as small coloured tiles, for people running ten
  or more.
- **Herd strip.** One tiny dot per agent along each side of the notch, coloured by state. The
  whole herd at a glance, without the pill opening.
- **Herd timeline.** A day view with one bar per agent, coloured by state, built from the
  transitions Shepherd observed (kept locally, small ring buffer). Shows where agents sat waiting
  on you. Also the best picture for the README.
- **Peek on hover.** Hovering a card shows the pane's current screen (`pane.read`), read only
  while hovered, so it costs nothing at idle.
- **Weekly recap.** Agent-hours, workspaces finished, busiest day, and how long agents waited on
  you. Local only, and only in the recap, never as a nag.
- **Day card.** Export the herd timeline as an image: a day of parallel agents as coloured bars,
  plus agent-hours and "waited on me: 12 min". Project names optional. Made to be shared; it shows
  parallelism, which a single-session recap cannot.

## Control

- **Broadcast.** Send one message to several agents at once, for example "rebase on main and rerun
  tests", skipping blocked ones.
- **Answer approvals from the notch.** For a `blocked` agent, show the approval text and the
  choices the agent offers, and send the chosen key (`agent.read`, `agent.send_keys`). Off by
  default and always showing the real dialog text, since a wrong answer is costly.
- **Talk to the herd.** Hold a hotkey and speak. On-device transcription (`SpeechAnalyzer`) turns it into text, the on-device model picks the agent by name or token (tool
  calling over the agent list), Shepherd shows the routed prompt for a one-key confirm, then
  sends it (`agent.prompt`). Nothing leaves the Mac.
- **Async questions.** A token convention (`question`) that an agent sets with
  `herdr pane report-metadata` to ask something without stopping. Shepherd shows it with a reply
  box and answers through `agent.prompt`. Works with any agent that can run a shell command, no
  hooks.
- **Rules.** Small JSON rules: "when <state or token condition>, run <action>", for example "when
  `review` becomes `changes_requested` and the agent is done, prompt it to address the review".
  Off by default, every automatic send logged and visible, one switch pauses all rules.
- **Review inbox.** "Done" is where the human's work starts. A lane of finished workspaces with
  diff stats and one key each to open in the editor, run tests, or hand off to a PR action.
  Open question: diff data from plugin tokens only, or may Shepherd read git directly?
- **Prompt snippets.** Reusable prompts in the palette with placeholders (`{branch}`,
  `{token.ticket}`), sent to one agent or broadcast.

## Intelligence

Local first; see PRD "Intelligence" for the rules every idea here follows.

- **Blocked question parsing.** The on-device model pulls the question and its choices out of an
  approval UI, so the notch can show real buttons. Feeds "Answer approvals from the notch".
- **Bring your own model.** An OpenAI-compatible endpoint in config (local Ollama or LM Studio, or
  a cloud key) for Macs without Apple Intelligence, or for better summaries. Plain `URLSession`.
- **Spoken readouts.** Optional `AVSpeechSynthesizer` line such as "the auth agent needs you",
  for when you are on another display or away from the keyboard. Also an accessibility win.
- **Handoff note.** When a workspace finishes, a short local summary of what the agent did across
  its turns, ready to paste into a PR description or a standup.

## Mac integration

- **Spotlight and Shortcuts.** App Intents for "agents that need me", "prompt agent", "start
  task", "focus agent". macOS 26 Spotlight runs intents directly, and Shortcuts, Raycast and
  Stream Deck users get automation for free. Needs the SwiftPM spike in the roadmap.
- **Focus filters.** `SetFocusFilterIntent`, so a "Meeting" Focus mutes Shepherd and a "Deep work"
  Focus only lets blocked agents through.
- **Widgets and Control Center controls.** A herd summary on the desktop and a control to pause
  alerts. Needs an app extension, which complicates the build; later.
- **Liquid Glass.** Use the system glass material for the notch pill and panel so
  Shepherd looks like part of the system.
- **Haptic nudge.** A light trackpad haptic when hovering the notch while something needs you.

## Personality

- **Sheepdog extras.** The base mascot is on the roadmap (0.1). Beyond it: a soft optional bark,
  the dog rounding up the herd strip dots, a happy run when the queue hits zero.
- **Sounds you can replace.** Drop files into a folder to override each sound.
- **Spatial sounds.** Pan each agent's sound left or right by its workspace position, so you hear
  which one finished. Off by default.
- **Seasonal touches,** off by default.

## Ecosystem

- **Token conventions.** Document a small set of well-known token names (`pr`, `ticket`,
  `review`, `diff_add`, `diff_del`, `question`) so plugin authors and Shepherd agree without
  coordination.
- **Example plugins.** Ship a couple of herdr plugins in an `examples/` folder (git diff badges,
  GitHub PR badges) that make Shepherd useful out of the box.
- **Themes.** Colour sets that match popular terminal themes.
- **Multiple herdr sessions and remote machines,** shown side by side. herdr already knows saved
  machines (`herdr --machine`), so this may need little more than one store per socket.
- **Cloud agent sources.** Background and cloud agents (Claude Code on the web, Codex cloud,
  Copilot coding agent, Cursor background agents) in the same queue as local ones, through their
  APIs. Opt-in, the first sources that use the network. A candidate for a paid tier.
- **iPhone and Watch companion.** Live Activity with herd state, push when an agent is blocked,
  answer approvals from the Lock Screen. Needs a sync path (the user's own iCloud, end-to-end
  encrypted). A candidate for a paid tier; Coucou already ships a free one, so it must be clearly
  better at many agents, not a copy.

## Contributors

- **Agent-friendly repo.** The fake herdr, view snapshots and the idle budget check together let
  a coding agent build, see and measure a UI change without a human running the app. Document that
  loop in `CLAUDE.md` once it exists.

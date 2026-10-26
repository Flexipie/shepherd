# Vision

Read this before building anything. It says what Shepherd is for, who it is for, and the bar a
change has to clear. [PRD.md](PRD.md) says how it is built; this says why and how well.

## The goal

Shepherd is a real product, built to be published on GitHub for every developer who runs coding
agents in parallel. Not a personal script, not a demo. Someone should be able to find the repo,
install it in a minute, and keep it running because it makes their day better.

The one-line pitch: **land more of your agents' work, with confidence, from anywhere on your Mac.
Start, unblock and decide on work from every coding agent you use, without living in their
terminals.**

Shepherd is a general tool for developers who run coding agents, not a herdr tool. herdr is the
first source of agents; Claude Code, Codex and cloud agents follow as source adapters (see
[STRATEGY.md](STRATEGY.md) and PRD "Sources"). Shepherd does not run agents itself. It owns the
developer's attention and the decisions between the agents.

## The core: confident merges per minute of attention

Agents are no longer the scarce part. Running five of them is easy, and the agent tools now ship
their own dashboards. What is scarce is the developer's attention, and the step that eats it is
deciding: is this finished work right, and is it safe to merge? Before merging, people go to the
agent and ask it what it changed, what it thinks is best, and what is risky. Studies of teams
using agents find more code but not more finished work, because review and verification became
the bottleneck.

So the number Shepherd maximises is **changes the developer is confident to merge, per minute of
their attention.** Every feature should help with one step of that loop:

1. **Start** work from anywhere in a few keys, in whichever agent and checkout fits.
2. **Stay quiet** while agents work, and earn every interruption.
3. **Unblock** an agent that needs a yes or an answer without leaving the app you are in.
4. **Decide** on finished work with what you would otherwise go to the terminal for: the agent's
   own account of what it did, its answers to your usual questions, and the facts (diff, tests,
   PR, other agents touching the same files). Then merge, follow up or send it back.

A feature that only shows the same state somewhere else is not enough on its own; the agent tools
already do that. The palette (⌥Space) is the centre of the loop.

## Who it is for

- **The parallel-agent developer.** Runs a few to fifteen agents at once across worktrees, in
  Claude Code, Codex, herdr or a mix. Their problem is attention: which agent needs me, which one
  finished, which one is stuck, what did each change, and can I trust it. They work in other apps
  (browser, Slack, editor) between checks.
- **The herdr power user.** Writes plugins and tunes `config.toml`. Wants a surface that renders
  what their plugins publish, and actions they can define without forking.
- **The contributor.** Wants to add a module or a source in an afternoon without understanding
  the whole app.

The author's own setup (Linear tickets, daisy reviews, PR badges) is one example of what a user
plugs in, not the product. Features must make sense for someone with a completely different
setup.

## What makes it good

Shepherd should feel like a well-made Mac utility (think the quality of the best menu bar apps),
not a dashboard bolted onto a terminal.

1. **Glanceable.** The menu bar and notch answer "does anything need me?" in under a second,
   without a click. Detail is one click away, never in the way.
2. **Calm.** Silent and invisible when nothing needs you. No badges that never clear, no
   notifications for things you did not ask about. Interruptions are earned.
3. **Fast and light.** Instant to open, no lag on updates, no CPU when idle, no fan. Performance
   is a feature and a regression is a bug.
4. **Correct.** Never show stale or wrong state as if it were current. If herdr is gone or the
   stream fell behind, say so and recover.
5. **Native.** Follows macOS conventions: system fonts and materials, light and dark mode,
   keyboard navigation, VoiceOver labels, Reduce Motion, multiple displays, Spaces, full screen.
6. **Yours.** Sensible defaults that work with zero config, and deep customisation (modules,
   token styling, actions) for those who want it, in plain JSON.
7. **Delightful, in that order.** Personality (a mascot, animation, sound) is welcome, but only
   on top of something that already works well and only if it can be turned off.

## Be creative

We want ideas. Shepherd sits between a developer and a herd of agents, and there is a lot of room
for things nobody has built yet. Agents working on this repo are encouraged to:

- propose features, interactions and visuals that go beyond the roadmap,
- prototype an idea behind a module that is off by default,
- question an existing decision when there is a better way, with reasons.

Write new ideas into [IDEAS.md](IDEAS.md). Open a GitHub issue for one only when it is
decided.

Creativity has guardrails. An idea is good for Shepherd when it:

- helps with attention, awareness or control of agents (the core job), or makes the app a joy to
  use without getting in the way,
- works for users other than the author,
- fits the architecture: sources (tmux, herdr, agent reports) and plugin tokens as data, a module
  as the unit,
- costs little at idle and can be disabled.

## The quality bar for shipping

A feature is done when:

- it works with the default config and degrades cleanly when data is missing (no herdr, no
  plugin tokens, no notch, a second display),
- it has tests for its logic, and the UI was checked by running the app against a real herdr,
- it has no measurable idle cost (check CPU and memory before and after),
- it handles light and dark mode, keyboard use and VoiceOver labels,
- its config, if any, is documented, and README or docs say what it does,
- it is small and readable: someone new could change it without reading the whole app.

Unfinished work stays behind a disabled module or on a branch, never half-visible in the default
experience.

## What a public release needs

These are part of the product, not afterthoughts:

- A README that sells it in one screen: a GIF or screenshot, the pitch, install in one command.
- Install paths: a signed and notarised download, and later a Homebrew cask.
- First run: detects herdr, explains what it found, works without a config file.
- Updates: tagged releases with changelogs.
- Privacy: everything stays local. Shepherd talks to its local sources only; no telemetry, no
  network calls unless the user turns on a source, action or endpoint that makes one. Say so in
  the README.
- Contributor docs: how to build, how to add a module, how to propose an idea.
- A stable config format: once released, changes are additive or migrated.

## Non-goals

- Replacing herdr or any agent's own UI. Shepherd sits on top of them.
- Reading terminals outside a source adapter. A source gets state from an API (herdr's socket, a
  cloud agent API), from agent reports, or from its terminal's screen (tmux) when nothing better
  exists. That code lives only inside the source's adapter; the rest of the app never knows how a
  source gets its state.
- Shipping an AI model. v1 has none. Any future intelligence is a small on-device helper, off by
  default (`docs/PRD.md`, "Intelligence").
- Being a general dashboard for other services. No music, payments or LLM chat. Integrations
  arrive as plugin tokens or as agent sources.
- Matching other apps on the number of agents supported. A few sources done well beat many done
  shallowly.
- Cross-platform. macOS first and only, done properly.

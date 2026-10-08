# Vision

Read this before building anything. It says what Shepherd is for, who it is for, and the bar a
change has to clear. [PRD.md](PRD.md) says how it is built; this says why and how well.

## The goal

Shepherd is a real product, built to be published on GitHub for every developer who runs coding
agents in herdr. Not a personal script, not a demo. Someone should be able to find the repo,
install it in a minute, and keep it running because it makes their day better.

The one-line pitch: **herdr runs your herd of agents; Shepherd lets you watch and steer it from
anywhere on your Mac.**

## Who it is for

- **The parallel-agent developer.** Runs several agents at once across herdr workspaces and
  worktrees. Their problem is attention: which agent needs me, which one finished, which one is
  stuck, and what did each change. They work in other apps (browser, Slack, editor) between
  checks.
- **The herdr power user.** Writes plugins and tunes `config.toml`. Wants a surface that renders
  what their plugins publish, and actions they can define without forking.
- **The contributor.** Wants to add a module in an afternoon without understanding the whole app.

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

Write new ideas into [IDEAS.md](IDEAS.md). Move one to [ROADMAP.md](ROADMAP.md) only when it is
decided.

Creativity has guardrails. An idea is good for Shepherd when it:

- helps with attention, awareness or control of agents (the core job), or makes the app a joy to
  use without getting in the way,
- works for users other than the author,
- fits the architecture: herdr's socket and plugin tokens as data, a module as the unit,
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
- Privacy: everything stays local. Shepherd talks to the local herdr socket only; no telemetry, no
  network calls unless a user-configured action makes one. Say so in the README.
- Contributor docs: how to build, how to add a module, how to propose an idea.
- A stable config format: once released, changes are additive or migrated.

## Non-goals

- Replacing herdr or duplicating its terminal UI. Shepherd is a companion.
- Collecting agent state on its own (hooks, terminal scraping). herdr owns state.
- Being a general dashboard for other services. Integrations arrive as herdr plugin tokens.
- Cross-platform. macOS first and only, done properly.

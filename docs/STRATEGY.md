# Strategy

Where Shepherd fits, what it competes with, and how it could grow. [VISION.md](VISION.md) holds the
principles; this doc holds the bets. Written October 2026; revisit when the landscape moves.

## Why it exists

First, a tool that makes the author's own parallel-agent work faster. If it is good at that, it is
a good open source tool for others. If it is very good, revenue is on the table. Decisions follow
that order: never trade daily usefulness for reach.

## The landscape

[Coucou](https://github.com/Louis-CFM/coucou) is a notch companion for agent sessions. It reached
about 4,200 stars in its first eleven days (released Sep 27, 2026) and ships near daily. It
already has:

- around a dozen agents (Claude Code, Codex, Cursor, Gemini CLI and more) through hooks,
- Allow and Deny approvals from the notch,
- an iPhone app with Live Activities and Face ID approvals, synced through iCloud,
- a weekly recap with a share image, demo mode, replaceable sounds, Focus filters, Siri.

Why it took off: a character (Mochi) that makes people smile and makes the GIF; support for
whatever agent you already use; one "wow" moment (approve from the Lock Screen); a shareable
image; a story ("the open version of what studios teased") and a fast release pace.

Where it is weak, which is our opening:

- It watches one session at a time. It does not help you run eight agents in parallel: no triage,
  no keyboard flow through a queue, no launching work, no reviewing what finished.
- It is a kitchen sink (music, payments, LLM chat). Charming, not a serious work tool.
- Per-agent hooks spread through the app, which break as agents change.

We do not compete on breadth or agent count. A solo project cannot win that race, and it is not
the job.

## Positioning

> **Coucou is a friend that tells you when an agent needs you. Shepherd is how you run a herd of
> them.**

A power tool for people running five to fifteen agents, with the polish of Linear or Superhuman:
inbox zero for your agents.

## Pillars

1. **The queue.** Everything that needs you, ranked: quick approvals, then questions, then
   finished work. Keyboard first. Answering eight agents takes thirty seconds.
2. **Launch.** Hotkey, pick a repo, type a task: a worktree and an agent, running.
3. **Review inbox.** Finished work with diff stats, one key to open, test or turn into a PR.
4. **Fewer interruptions over time.** Spot repeated approvals and suggest allowlisting them.
5. **Local and cloud agents in one place.** Parallel work is moving to background and cloud
   agents; Shepherd shows them next to local ones.

Ideas behind each pillar are in [IDEAS.md](IDEAS.md); decided ones are in
[ROADMAP.md](ROADMAP.md).

## Sources

Shepherd is not herdr-only. Agents arrive through source adapters onto one herd model (PRD
"Sources"):

1. **herdr** through public 0.1. The richest source (state, control, worktrees), and the one the
   author uses daily, so dogfooding stays honest.
2. **Claude Code directly**, after 0.1. Where most of the audience is. Uses hooks, contained in
   its adapter.
3. **Cloud agents** through their APIs. The clearest differentiator.

The seam goes in during milestone 1, while it is cheap.

## Getting noticed

- **The sheepdog** ships in 0.1. It herds, which is the product in one picture, and it is the GIF.
  Secondary to the work and easy to turn off.
- **The day card**: the herd timeline as a shareable image. It shows parallelism, which a
  single-session recap cannot.
- **Demo mode**, so anyone can try it without herdr, and the GIF is reproducible.
- Launch in herdr's community first, then Show HN at 0.1.
- Measure without telemetry: GitHub release downloads, Homebrew cask analytics, stars.
- Talk to the herdr author early: a listing on herdr.dev, and API requests (state timestamps)
  that help both projects.

## What we will not do

- Chat with an LLM, music, payments or any non-agent integration.
- Windows or Linux.
- Chase other apps' agent count.

## Revenue, later

The Mac app stays free and MIT; the name and the sheepdog stay reserved. If a paid tier happens,
the candidates are cloud agent sources, the iPhone and Watch companion, and team features.
Coucou gives its iPhone app away, so cloud sources and team features are the more defensible.
Keep candidate features in separate targets so the split stays clean, and settle licensing before
outside contributions grow.

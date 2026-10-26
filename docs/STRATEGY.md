# Strategy

Where Shepherd fits, what it competes with, and how it could grow. [VISION.md](VISION.md) holds the
principles; this doc holds the bets. Written October 2026; revisit when the landscape moves.

## Why it exists

First, a tool that makes the author's own parallel-agent work faster. If it is good at that, it is
a good open source tool for others. If it is very good, revenue is on the table. Decisions follow
that order: never trade daily usefulness for reach.

## The landscape

Updated October 17, 2026, after a survey of the field.

**The field is crowded where Shepherd started.** The awesome-agent-orchestrators list has about 275
projects, about 80 of them desktop or web apps for parallel agents (herdr is on it). Menu bar
status apps on Claude Code's hooks are common (Claude Island, Hawky, AgentBar, claude-status-bar),
one shows permission prompts in the notch (DockTerm), and worktree apps (Conductor, Superset,
Nimbalyst, Claude Squad) are many.

**The agent tools are absorbing the basics.** Claude Code's agent view (`claude agents`, research
preview since May 2026) groups sessions by state, writes a one-line summary per session, and lets
you peek, reply, dispatch new background sessions and see PR status, each session in its own
worktree. Auto mode (March 2026) answers most approval prompts with a classifier; users accepted
about 93% of prompts anyway. So seeing state, jumping, replying and fewer approvals are becoming
free inside each tool. They cover one tool, in its terminal.

**The bottleneck moved to review and trust.** A Harvard working paper on 718 firms found about 30%
more code but no measurable rise in finished work, with review taking 49% longer; developer
surveys agree. Practitioners put their limit at two or three parallel threads and describe
hopping between terminals as burnout. Simon Willison can review and land one significant change
at a time, and runs research and small tasks in parallel.

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

Where it and the rest of the field are weak, which is our opening:

- Nobody helps with the merge decision. Tools show state and diffs; none bring the agent's own
  account, your usual questions and the facts together so you can decide without the terminal.
- They are one tool each. Agent view is Claude only and in a terminal; the notifiers watch, they
  do not let you start, unblock and decide across tools from anywhere on the Mac.
- Coucou watches one session at a time: no triage, no launching work, no reviewing what finished.
- It is a kitchen sink (music, payments, LLM chat). Charming, not a serious work tool.
- Per-agent hooks spread through the app, which break as agents change.

We do not compete on breadth or agent count. A solo project cannot win that race, and it is not
the job.

## Positioning

> **The agent tools run your agents. Shepherd is where you decide on their work: start, unblock
> and land it from anywhere on your Mac, across every agent you use.**

What it maximises: changes you are confident to merge, per minute of your attention (VISION
"The core"). With the polish of Linear or Superhuman: inbox zero for your agents' work.

## Pillars

1. **Ready to land.** For finished work, what you would go to the terminal for: the agent's final
   message, its answers to your saved questions (one key, or automatic as a setting), and the
   facts (diff, tests, PR, overlap with other agents). One key to merge, follow up or send back.
2. **Start from anywhere.** ⌥Space, a repo, a prompt: an agent in a tmux pane, in herdr, in a
   Claude Code background session or in a new terminal window. Scouts too: a question whose answer comes
   back to the palette, not a diff.
3. **The queue.** Everything that needs you, ranked, keyboard first, answered without leaving the
   app you are in.
4. **Every agent in one place.** Any coding agent in a terminal (tmux and agent reports), with
   herdr and Claude Code as optional adapters; cloud agents later.

Dropped as a pillar: fewer approvals by suggesting allowlists. Auto mode now does most of that
inside Claude Code.

Ideas behind each pillar are in [IDEAS.md](IDEAS.md); decided ones are GitHub issues (see
[ROADMAP.md](ROADMAP.md)).

## Sources

Shepherd is for any coding agent in a terminal, not only herdr users. Agents arrive through source
adapters onto one herd model (PRD "Sources"):

1. **tmux** first. It works in every terminal, so any CLI agent in a pane can be seen, read,
   answered and started from Shepherd. Its screen reads are inferred, not reported.
2. **Agent reports** (`shepherd report`). Any agent that can run a shell command states its own
   status through its hooks, rules or skills. This is what makes state exact without tmux.
3. **herdr**, as an optional adapter. The richest source for people who use it (state, control,
   worktrees).
4. **Claude Code's session files**, as an optional adapter. Where most of the audience is.
5. **Cloud agents** through their APIs. The clearest differentiator, later.

The seam goes in during milestone 1, while it is cheap.

## Getting noticed

- **The sheepdog** ships in 0.1. It herds, which is the product in one picture, and it is the GIF.
  Secondary to the work and easy to turn off.
- **The day card**: the herd timeline as a shareable image. It shows parallelism, which a
  single-session recap cannot.
- **Demo mode**, so anyone can try it without herdr, and the GIF is reproducible.
- Launch where terminal-agent users are (the herdr and tmux communities first), then Show HN at 0.1.
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

# Roadmap

Open work lives in [GitHub issues](https://github.com/Flexipie/shepherd/issues), grouped by
[milestone](https://github.com/Flexipie/shepherd/milestones). This page keeps only the order and
what each milestone must achieve. When an issue ships, close it and add its entry to the end of
[SHIPPED.md](SHIPPED.md).

Ideas that are not decided stay in [IDEAS.md](IDEAS.md) and get an issue only once decided.

## Milestones, in the order they will be worked on

1. [M5: UI and UX pass](https://github.com/Flexipie/shepherd/milestone/1). Done before any new
   gadget. Done when: the daily-use list is done, and adding a gadget touches only its module and
   one view.
2. [Any terminal agent](https://github.com/Flexipie/shepherd/milestone/2). Shepherd for any coding
   agent that runs in a terminal, not only herdr; built before "ready to land" so the decide step
   works for every agent. Done when: someone with tmux, Claude Code or Codex (or both) and no herdr
   sees their agents in the notch, answers an approval, and starts a new task from the palette.
3. [Ready to land](https://github.com/Flexipie/shepherd/milestone/3). The core loop's decide step
   (VISION "The core"), built on the same plugin extension points users get (PRD "Plugins").
   Done when: a finished agent's work can be decided on from the palette, without opening its
   terminal, most of the time.
4. [Start from anywhere](https://github.com/Flexipie/shepherd/milestone/4), and Claude Code as a
   source.
5. [M6: More from anywhere](https://github.com/Flexipie/shepherd/milestone/5).
6. [M7: A second source](https://github.com/Flexipie/shepherd/milestone/6). Done when: someone who
   has never installed herdr runs three Claude Code sessions and works their needs-you queue from
   Shepherd.
7. [Public 0.1](https://github.com/Flexipie/shepherd/milestone/7). Not started until we decide to
   publish. Done when: a stranger installs it from the README in a minute and it works with their
   herd.
8. [Later](https://github.com/Flexipie/shepherd/milestone/8). Decided, not scheduled.

Outside the milestones:
[manual checks](https://github.com/Flexipie/shepherd/issues?q=is%3Aopen+label%3Amanual-check)
that need a person, real agents or other hardware, and follow-ups (open issues with no
milestone).

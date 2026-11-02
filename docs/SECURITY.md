# Security

## Reporting a problem

Report a security problem privately, not in a public issue: open the repository's
[Security tab](https://github.com/Flexipie/shepherd/security) and choose **Report a
vulnerability**. Only the maintainer sees it. Say what you found, how to reproduce it, and which
commit you built.

Once it is fixed, the fix lands on `main`, and you are credited in the advisory unless you would
rather not be.

Only the latest code on `main` is supported.

## What Shepherd trusts

Shepherd runs on your Mac with your permissions and talks to nothing outside it (see "Privacy" in
the [README](../README.md)). Some of what it does is trusted by design, and is not a
vulnerability on its own:

- **Plugins are your own code.** A plugin in `~/.config/shepherd/plugins/` runs with your
  permissions when the palette opens, when you pick one of its actions, and on the agent events
  it asks for. Shepherd does not sandbox or check them. Only add plugins you have read.
- **Your config is trusted.** `~/.config/shepherd/config.json` can set extra arguments for the
  agents a new task starts, including ones that let an agent run commands without asking.
- **Agents' local channels are trusted.** herdr's socket, tmux's sockets and the agent report
  folder are your user's own. Anything running as your user can already write to them.

Problems we do want to hear about include: text from an agent's screen, a report or herdr making
Shepherd run a command or type into a pane you did not choose; `shepherd-report install` changing
more than its own entries in an agent's settings; Shepherd making a network request it should not;
or another user on the Mac being able to reach any of the above.

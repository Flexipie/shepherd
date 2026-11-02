# Example plugins

Copy or symlink a folder into `~/.config/shepherd/plugins/`, then open the palette (⌥Space).
"Plugins" in `docs/PRD.md` describes the manifest, what a command gets and what it may print.

- `herdr-actions`: every herdr plugin action in the palette. Global ones are commands; workspace
  ones show on ⌘K for a herdr project. Needs `herdr` and `jq`.
- `load-average`: a gadget, the Mac's load average for 1, 5 and 15 minutes as meters, full at
  one process per core. Shows on the Gadgets tab and the palette's "Gadgets" page.
- `diff-stat`: ⌘K on a project or agent, "Show what changed": git's diff stat against
  `origin/main`, and the totals as `diff_files`, `diff_add` and `diff_del` tokens. Needs `jq`.

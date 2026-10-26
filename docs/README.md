# Docs

| Doc | What it is | Status |
| --- | --- | --- |
| [VISION.md](VISION.md) | Who Shepherd is for, product principles, the quality bar, and how to be creative here. Read first | Current |
| [STRATEGY.md](STRATEGY.md) | Positioning, the landscape (Coucou), sources order, growth and revenue bets | Current |
| [IDEAS.md](IDEAS.md) | Open idea bank, nothing decided | Open |
| [PRD.md](PRD.md) | What Shepherd is, the architecture, data flow, and how to add a module | Current |
| [ROADMAP.md](ROADMAP.md) | Milestone order and what each must achieve; open work is in GitHub issues | Current |
| [SHIPPED.md](SHIPPED.md) | What is built, oldest first | Current |
| [CHANGELOG.md](CHANGELOG.md) | What each release gives users, newest first | Current |

## Releasing

Only the maintainer tags and publishes. Until signed builds land
([#56](https://github.com/Flexipie/shepherd/issues/56)) a release is a tag and notes, with no
binary: users build from source.

1. In a PR: rename `## [Unreleased]` in [CHANGELOG.md](CHANGELOG.md) to `## [x.y.z] - YYYY-MM-DD`
   with its link line at the bottom (0.1.0 only needs its date), and set the same version in
   `scripts/bundle.sh`. Merge it.
2. Take the notes from the merged `main`, tag it, and publish the section as a draft release. The
   `awk` joins wrapped lines, since GitHub keeps line breaks in release notes. Check the draft,
   then publish it.

```bash
v=0.1.0
git fetch origin main
git show origin/main:docs/CHANGELOG.md | awk -v v="$v" '
  $0 ~ "^## \\[" v "\\]" { on = 1; next }
  /^## \[|^\[/ { on = 0 }
  !on { next }
  $0 != "" && prev != "" && $0 !~ /^ *(- |#)/ { sub(/^ +/, ""); out = out " " $0; prev = $0; next }
  { if (started) print out; out = $0; prev = $0; started = 1 }
  END { if (started) print out }
' >/tmp/notes.md
test -s /tmp/notes.md && git tag -a "v$v" -m "Shepherd $v" origin/main && git push origin "v$v" &&
  gh release create "v$v" --draft --verify-tag --title "Shepherd $v" --notes-file /tmp/notes.md
```

3. Start the next section: add `## [Unreleased]` above the released one, for the changes that
   follow.

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

1. In a PR: give the version's section in [CHANGELOG.md](CHANGELOG.md) its date and set the same
   version in `scripts/bundle.sh`. Merge it.
2. Tag `main` and publish the section as the release notes:

```bash
v=0.1.0
git tag "v$v" && git push origin "v$v"
awk -v v="$v" '$0 ~ "^## \\[" v "\\]" {on=1; next} /^## \[|^\[/ {on=0} on' docs/CHANGELOG.md >/tmp/notes.md
gh release create "v$v" --title "Shepherd $v" --notes-file /tmp/notes.md
```

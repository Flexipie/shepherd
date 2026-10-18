#!/bin/sh
# What the checkout changed since it left origin/main (or main): git's stat as the result, and
# the totals as tokens ($diff_files, $diff_add, $diff_del) on the project or agent. Needs jq.
set -eu
dir="${SHEPHERD_CWD:-}"
[ -n "$dir" ] && [ -d "$dir" ] || { echo "No folder known for this target" >&2; exit 1; }
cd "$dir"
base=$(git merge-base origin/main HEAD 2>/dev/null || git merge-base main HEAD)
stat=$(git diff --stat "$base")
set -- $(git diff --shortstat "$base" | awk '{a = 0; d = 0
  for (i = 1; i <= NF; i++) { if ($i ~ /insertion/) a = $(i-1); if ($i ~ /deletion/) d = $(i-1) }
  print $1 + 0, a + 0, d + 0}')
[ $# -eq 3 ] || set -- 0 0 0
[ -n "$stat" ] || stat="No changes since $(git rev-parse --short "$base")"
jq -n --arg text "$stat" --arg f "$1 files" --arg a "+$2" --arg d "-$3" \
  '{text: $text, tokens: {diff_files: $f, diff_add: $a, diff_del: $d}}'

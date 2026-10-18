#!/bin/sh
# Lists herdr's plugin actions as Shepherd actions. herdr's "workspace" actions become project
# actions (invoke.sh switches herdr to that workspace first), its "global" ones global actions.
# Needs herdr and jq on PATH.
set -eu
herdr="${HERDR_BIN_PATH:-herdr}"
"$herdr" plugin action list | jq '{actions: [
  .result.actions[]
  | select((.platforms // ["macos"]) | index("macos"))
  | . as $a
  | ((.contexts // ["global"]) | map(if . == "workspace" then "project" else . end)
     | map(select(. == "global" or . == "project")) | unique)[]
  | {id: "\($a.plugin_id).\($a.action_id).\(.)", title: $a.title, context: ., symbol: "puzzlepiece",
     command: ["sh", "invoke.sh", $a.plugin_id, $a.action_id]}
]}'

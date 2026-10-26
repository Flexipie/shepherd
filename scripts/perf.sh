#!/usr/bin/env bash
# Idle budget check (docs/PRD.md, "Performance budget"): runs the release app against fake herdr,
# with every path pointed at a temp folder, and fails if idle CPU or physical footprint is over.
# PERF_SECONDS (default 30) is the measured window; PERF_CPU_LIMIT (percent, default 0.5) and
# PERF_MEMORY_LIMIT_MB (default 60) are the limits.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
seconds="${PERF_SECONDS:-30}"
cpu_limit="${PERF_CPU_LIMIT:-0.5}"
memory_limit="${PERF_MEMORY_LIMIT_MB:-60}"
settle=5

"$root/scripts/bundle.sh" release >/dev/null
swift build --package-path "$root" -c release --product FakeHerdr >/dev/null
bin="$(swift build --package-path "$root" -c release --show-bin-path)"

# Under /tmp, not $TMPDIR: a socket path must fit in 104 bytes.
work="$(mktemp -d /tmp/shepherd-perf.XXXXXX)"
fake_pid=""
app_pid=""
cleanup() {
    [[ -n "$app_pid" ]] && kill "$app_pid" 2>/dev/null || true
    [[ -n "$fake_pid" ]] && kill "$fake_pid" 2>/dev/null || true
    exec 3>&-
    wait 2>/dev/null || true
    rm -rf "$work"
}
trap cleanup EXIT
# A write to a fake that died fails with an error, through the trap, instead of killing the script.
trap '' PIPE

# The fake reads commands from stdin and quits at its end; a FIFO this script holds open keeps
# it running until cleanup.
socket="$work/herdr.sock"
mkfifo "$work/stdin"
"$bin/FakeHerdr" "$socket" <"$work/stdin" >"$work/fake.log" 2>&1 &
fake_pid=$!
exec 3>"$work/stdin"
for _ in $(seq 50); do [[ -S "$socket" ]] && break; sleep 0.1; done
[[ -S "$socket" ]] || { echo "perf: fake herdr did not start" >&2; cat "$work/fake.log" >&2; exit 1; }

# herdr only: tmux and the report spool would read the machine's real agents. No hotkeys, so a
# running Shepherd keeps its own.
echo '{ "sources": ["herdr"], "hotkeys": { "next": null, "palette": null } }' >"$work/config.json"
mkdir -p "$work/plugins" "$work/spool" "$work/claude"

HERDR_SOCKET_PATH="$socket" \
SHEPHERD_CONFIG_PATH="$work/config.json" \
SHEPHERD_TRANSITION_LOG="$work/transitions.jsonl" \
SHEPHERD_PLUGINS_PATH="$work/plugins" \
SHEPHERD_SPOOL_DIR="$work/spool" \
HERDR_CONFIG_PATH="$work/herdr.toml" \
CLAUDE_CONFIG_DIR="$work/claude" \
SHEPHERD_OPENUSAGE_URL="http://127.0.0.1:9" \
    "$root/build/Shepherd.app/Contents/MacOS/Shepherd" >"$work/app.log" 2>&1 &
app_pid=$!

# CPU time from ps ("[hh:]mm:ss.cc") in seconds.
cpu_seconds() {
    { ps -o time= -p "$app_pid" || true; } | awk '{
        n = split($1, part, ":"); total = 0
        for (i = 1; i <= n; i++) total = total * 60 + part[i]
        print total }'
}

alive() {
    kill -0 "$app_pid" 2>/dev/null || { echo "perf: Shepherd exited" >&2; cat "$work/app.log" >&2; exit 1; }
}
number() { [[ "$1" =~ ^[0-9]+(\.[0-9]+)?$ ]] || { echo "perf: could not read $2 (got '$1')" >&2; exit 1; }; }

sleep "$settle"
alive
before="$(cpu_seconds)"
sleep "$seconds"
alive
after="$(cpu_seconds)"
number "$before" "CPU time"
number "$after" "CPU time"
cpu="$(awk -v a="$after" -v b="$before" -v s="$seconds" 'BEGIN { printf "%.2f", (a - b) / s * 100 }')"

# "Footprint: 14 MB" (or KB, GB) on footprint's first line for the process.
memory="$(footprint "$app_pid" | awk '/Footprint:/ {
    for (i = 1; i <= NF; i++) if ($i == "Footprint:") { v = $(i + 1); u = $(i + 2) }
    if (u == "KB") v /= 1024; else if (u == "GB") v *= 1024; else if (u == "B") v /= 1048576
    printf "%.1f", v; exit }')"
number "$memory" "the footprint"

# An app that never reached the fake would idle too: a blocked agent must reach the transition log.
lines() { [[ -f "$work/transitions.jsonl" ]] && wc -l <"$work/transitions.jsonl" || echo 0; }
logged="$(lines)"
echo "block w1:p1" >&3
for _ in $(seq 50); do (( $(lines) > logged )) && break; sleep 0.1; done
(( $(lines) > logged )) || {
    echo "perf: Shepherd never showed fake herdr's agents" >&2
    cat "$work/app.log" "$work/fake.log" >&2
    exit 1
}

status=0
cpu_ok="$(awk -v c="$cpu" -v l="$cpu_limit" 'BEGIN { print (c <= l) ? "ok" : "OVER" }')"
memory_ok="$(awk -v m="$memory" -v l="$memory_limit" 'BEGIN { print (m <= l) ? "ok" : "OVER" }')"
[[ "$cpu_ok" == ok && "$memory_ok" == ok ]] || status=1

echo "idle CPU over ${seconds} s: ${cpu}% (limit ${cpu_limit}%) ${cpu_ok}"
echo "footprint at idle: ${memory} MB (limit ${memory_limit} MB) ${memory_ok}"
echo "not measured here: footprint after opening the bar and the palette (by hand, see docs/PRD.md)"
exit "$status"

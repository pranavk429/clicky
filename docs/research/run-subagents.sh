#!/usr/bin/env bash
# Launches one Gemini 3.8 Flash (High) research subagent per track via the Antigravity CLI.
# Research-only prompts; reports are captured from stdout into docs/research/reports/.
# Staggered start + up to 3 retries per track because the CLI occasionally hits transient network errors.
# Usage: ./run-subagents.sh [track-prefix ...]   (default: all six)
set -u
ROOT="/Users/pranav1296/clicky/docs/research"
mkdir -p "$ROOT/reports" "$ROOT/logs"
PREAMBLE="$(cat "$ROOT/prompts/_preamble.txt")"
TRACKS=("$@")
if [ ${#TRACKS[@]} -eq 0 ]; then TRACKS=(01 02 03 04 05 06); fi
run_track() {
  local f="$1" name
  name="$(basename "$f" .txt)"
  for attempt in 1 2 3; do
    agy --model gemini-3.8-flash-high --effort high --print-timeout 25m \
      -p "${PREAMBLE}
$(cat "$f")" \
      > "$ROOT/reports/${name}.md" 2> "$ROOT/logs/${name}.log"
    echo "attempt=${attempt} exit=$?" >> "$ROOT/logs/${name}.log"
    [ -s "$ROOT/reports/${name}.md" ] && break
    sleep $((attempt * 20))
  done
}
for t in "${TRACKS[@]}"; do
  f="$(ls "$ROOT"/prompts/${t}-*.txt | head -n1)"
  run_track "$f" &
  sleep 8
done
wait
echo "all subagents finished"

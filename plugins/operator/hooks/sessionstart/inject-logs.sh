#!/bin/bash
# ======================================================
# @file inject-logs.sh - recent log threads into context
# ======================================================
# @description
# - fires at session start: injects the newest log threads under a `## recent threads` heading
# - stubs today's log file when none exists, the one action that still does (see #1)
# - reads its thread count from the log skill's own budget, defaulting to 4 when it is absent
# - the harness caps one payload at 10000 characters, so oldest threads drop until the batch fits
# - no threads at all injects nothing, so a fresh project pays nothing
# - anchors to the project root first, since a subdirectory cwd stubs a stray log and injects it
# - #1: the demand actions treat a missing log as nothing, so the stub they rely on lives here
# @see plugins/retardify/skills/log/, plugins/operator/hooks/hooks.json, .construct/retardify/log/

command -v jq >/dev/null 2>&1 || exit 0

# hooks inherit the session's cwd, so anchor first; every path below stays relative to the root
cd "${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}" || exit 0

TODAY_LOG=".construct/retardify/log/$(date +%Y-%m-%d).md"
# the 10000-char harness cap, with headroom so the heading and seams never spill over it
PAYLOAD_BUDGET=9500

# stub today's log file if one doesn't exist
if [ ! -f "$TODAY_LOG" ];
then mkdir -p .construct/retardify/log; echo "# $TODAY_LOG" > "$TODAY_LOG"; fi

# the log skill owns its own budget; a missing log skill falls back rather than injecting nothing
LOG_SKILL="$(dirname "${BASH_SOURCE[0]}")/../../../retardify/skills/log/log.sh"
INJECT_THREADS=$(bash "$LOG_SKILL" --budget 2>/dev/null | sed -n 's/^inject_threads: //p')
INJECT_THREADS=${INJECT_THREADS:-4}

# list every thread as "file<TAB>start<TAB>end", oldest first (so newest are the tail)
# threads begin at the `## Thread` heading to the line before the next one
all_threads() {
  local file total
  for file in $(ls -1 .construct/retardify/log/*.md 2>/dev/null | sort); do
    [ -e "$file" ] || continue
    total=$(wc -l < "$file" | tr -d ' ')
    awk -v f="$file" -v total="$total" '
      /^## Thread #/ { if (s) print f "\t" s "\t" NR - 1; s = NR; next }
      END { if (s) print f "\t" s "\t" total }
    ' "$file"
  done
}

# the newest N threads, emitted oldest first so the reader meets them in the order they happened.
# each carries the day it came from, since that context lives in the filename and nowhere else
collect_threads() {
  local want=$1 file start end out=''
  while IFS=$'\t' read -r file start end; do
    [ -n "$file" ] || continue
    out="$out### from $(basename "$file" .md)"$'\n'"$(sed -n "${start},${end}p" "$file")"$'\n\n'
  done < <(all_threads | tail -n "$want")
  printf '%s' "$out"
}

THREADS=$(collect_threads "$INJECT_THREADS")
[ -n "$THREADS" ] || exit 0

# drop the oldest thread until the payload fits the cap, so what lands is whole rather than cut
while [ ${#THREADS} -gt "$PAYLOAD_BUDGET" ] && [ "$INJECT_THREADS" -gt 1 ]; do
  INJECT_THREADS=$((INJECT_THREADS - 1))
  THREADS=$(collect_threads "$INJECT_THREADS")
done

jq -n --arg ctx "## recent threads

$THREADS" \
  '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $ctx}}'

exit 0

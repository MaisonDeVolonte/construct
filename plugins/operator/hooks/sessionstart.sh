#!/bin/bash
# ====================================================
# @file sessionstart.sh - injects context into session
# ====================================================
# @description
# - injects the project's README.md and recent logs into session context
# - runs before user begins typing
# - stubs today's log file if none exists yet
# @see plugins/retardify/skills/log/, plugins/operator/hooks/, .construct/retardify/log/

TODAY_LOG=".construct/retardify/log/$(date +%Y-%m-%d).md"
READ_ME="README.md"

# stub today's log file if one doesn't exist
if [ ! -f "$TODAY_LOG" ];
then mkdir -p .construct/retardify/log; echo "# $TODAY_LOG" > "$TODAY_LOG"; fi

# the log skill owns its own budget; a missing log skill falls back rather than injecting nothing
LOG_SKILL="$(dirname "${BASH_SOURCE[0]}")/../../retardify/skills/log/log.sh"
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
if [ -z "$THREADS" ]; then THREADS="(no logged threads yet)"; fi

if [ -f "$READ_ME" ];
then README_FULL=$(cat "$READ_ME")
else README_FULL="(README.md not found)"; fi

# inject files into session context
jq -n \
  --arg readMe "$README_FULL" \
  --arg threads "$THREADS" \
  '{
    hookSpecificOutput: {
      hookEventName: "SessionStart",
      additionalContext: ($readMe + "\n\n## recent threads\n\n" + $threads)
    }
  }'

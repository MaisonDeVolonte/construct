#!/bin/bash
# =================================================
# @file sessionstart.sh - session start hook script
# =================================================
# @description
# - runs before user begins typing
# - creates today's log file if none exists yet
# - injects the most recent whole threads plus README.md into session context
# - never truncates: a thread is capped where it is written, so the reader spends a known budget
# - threads are taken newest first across days, so a quiet today still carries yesterday forward
# - injects HOST project context only; plugin context is never this hook's job
# - skills advertise themselves by frontmatter, so the loader lists them without help from here
# - output styles apply through the outputStyle setting, which is read before any hook runs
# - works with `claude`; does not work with `grok`
# @see plugins/retardify/skills/log/SKILL.md, plugins/operator/hooks/hooks.json, .operator/logs/

TODAY_LOG=".operator/logs/$(date +%Y-%m-%d).md"
READ_ME="README.md"

# make today's log file if one doesn't exist
if [ ! -f "$TODAY_LOG" ];
then mkdir -p .operator/logs; echo "# $TODAY_LOG" > "$TODAY_LOG"; fi

# the log skill owns its own budget, so this hook asks rather than keeping a second copy that
# would drift; a missing skill falls back rather than injecting nothing
LOG_SKILL="$(dirname "${BASH_SOURCE[0]}")/../../retardify/skills/log/log.sh"
INJECT_THREADS=$(bash "$LOG_SKILL" --budget 2>/dev/null | sed -n 's/^inject_threads: //p')
INJECT_THREADS=${INJECT_THREADS:-4}

# every thread in the archive as "file<TAB>start<TAB>end", oldest first, so the newest N are just
# the tail of that list. a thread runs from its `## Thread` heading to the line before the next one
all_threads() {
  local file total
  for file in $(ls -1 .operator/logs/*.md 2>/dev/null | sort); do
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

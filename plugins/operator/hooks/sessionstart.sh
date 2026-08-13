#!/bin/bash
# ====================================================
# @file sessionstart.sh - injects context into session
# ====================================================
# @description
# - injects the project's README.md and recent logs into session context
# - runs before user begins typing
# - stubs today's log file if none exists yet
# - anchors to the project root first, since a subdirectory cwd stubs a stray log and injects it
# @see plugins/retardify/skills/log/, plugins/operator/hooks/, .construct/retardify/log/

# hooks inherit the session's cwd, so anchor first; every path below stays relative to the root
cd "${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}" || exit 0

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

TREE_MAX_ROWS=20

# a coarse age is enough: the reader needs live work separated from abandoned work, not a clock
ago() {
  local secs=$(( $(date +%s) - $1 ))
  if [ "$secs" -lt 90 ]; then echo "now"
  elif [ "$secs" -lt 5400 ]; then echo "$((secs / 60))m ago"
  elif [ "$secs" -lt 172800 ]; then echo "$((secs / 3600))h ago"
  else echo "$((secs / 86400))d ago"; fi
}

# a session that has written nothing owns none of these paths, so each one is another agent's work
# by definition; that is what keeps the block cheap and free of any per-session write ledger
working_tree() {
  local total mtime
  total=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  if [ "$total" -eq 0 ]; then echo "working tree clean; no other agent has work in flight here"; return 0; fi
  echo "branch: $(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
  git status --porcelain 2>/dev/null | head -n "$TREE_MAX_ROWS" | while read -r code path; do
    [ -n "$path" ] || continue
    mtime=$(stat -f %m "$path" 2>/dev/null || stat -c %Y "$path" 2>/dev/null || echo 0)
    printf '%-3s %-52s %s\n' "$code" "$path" "$(ago "$mtime")"
  done
  if [ "$total" -gt "$TREE_MAX_ROWS" ]; then echo "+$((total - TREE_MAX_ROWS)) more"; fi
  echo "stashes: $(git stash list 2>/dev/null | wc -l | tr -d ' ') | worktrees: $(git worktree list 2>/dev/null | wc -l | tr -d ' ')"
  echo "every path above changed before this session started, so another agent owns it"
  echo "do not stage, revert, reformat or commit one; if your work needs it, say so and stop"
}

TREE=$(working_tree)

if [ -f "$READ_ME" ];
then README_FULL=$(cat "$READ_ME")
else README_FULL="(README.md not found)"; fi

# inject files into session context
jq -n \
  --arg readMe "$README_FULL" \
  --arg threads "$THREADS" \
  --arg tree "$TREE" \
  '{
    hookSpecificOutput: {
      hookEventName: "SessionStart",
      additionalContext: ($readMe + "\n\n## working tree\n\n" + $tree + "\n\n## recent threads\n\n" + $threads)
    }
  }'

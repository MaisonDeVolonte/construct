#!/bin/bash
# =============================================================
# @file inject-changes.sh - dirty paths and owners into context
# =============================================================
# @description
# - fires at session start: injects the working tree snapshot under a `## working tree` heading
# - prints the branch, every dirty path with a coarse age, then the stash and worktree counts
# - a session that has written nothing owns none of these paths, so each one is another agent's
# - closes on the directive naming who owns the paths, which is what stops a foreign revert
# - budgeted in characters rather than rows, since the block's whole job is to name every path
# - a row cap hid 6 paths on a 26-path tree, and an agent cannot avoid what it was never told
# - the budget only binds a pathological tree: 4000 chars carries roughly 55 paths (see #1)
# - anchors to the project root first, so the snapshot reads the repo rather than a subdirectory
# - self-contained on purpose: a manual install copies this one file and registers it
# - #1: lengths are counted in characters, matching the unit the harness caps payloads in
# @see plugins/operator/hooks/hooks.json, plugins/operator/skills/context/SKILL.md, plugins/gitgud/skills/deliver/SKILL.md

command -v jq >/dev/null 2>&1 || exit 0

# hooks inherit the session's cwd, so anchor first; every path below stays relative to the root
cd "${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}" || exit 0

# what the rows may spend; the heading, branch, counts and directives sit outside it and are fixed
TREE_BUDGET=4000

# a coarse age is enough: the reader needs live work separated from abandoned work, not a clock
ago() {
  local secs=$(( $(date +%s) - $1 ))
  if [ "$secs" -lt 90 ]; then echo "now"
  elif [ "$secs" -lt 5400 ]; then echo "$((secs / 60))m ago"
  elif [ "$secs" -lt 172800 ]; then echo "$((secs / 3600))h ago"
  else echo "$((secs / 86400))d ago"; fi
}

# one row per dirty path, oldest git-status order, so the list reads the same way twice running
rows_of() {
  local code path mtime
  git status --porcelain 2>/dev/null | while read -r code path; do
    [ -n "$path" ] || continue
    mtime=$(stat -f %m "$path" 2>/dev/null || stat -c %Y "$path" 2>/dev/null || echo 0)
    printf '%-3s %-52s %s\n' "$code" "$path" "$(ago "$mtime")"
  done
}

# whole rows up to a character budget, so a truncated tree still ends on a complete path
fit_rows() {
  local budget=$1 out='' used=0 line len
  while IFS= read -r line; do
    len=$(( ${#line} + 1 ))
    if [ $((used + len)) -gt "$budget" ]; then break; fi
    used=$((used + len))
    out="$out$line"$'\n'
  done
  printf '%s' "$out"
}

# a session that has written nothing owns none of these paths, so each one is another agent's work
# by definition; that is what keeps the block cheap and free of any per-session write ledger
working_tree() {
  local total kept shown=0
  total=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  if [ "$total" -eq 0 ]; then echo "working tree clean; no other agent has work in flight here"; return 0; fi
  echo "branch: $(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
  # the substitution below strips the trailing newline, so restore it before counting or printing:
  # without it the tail glues onto the last row and the count reads one short of the truth
  kept=$(rows_of | fit_rows "$TREE_BUDGET")
  if [ -n "$kept" ]; then
    printf '%s\n' "$kept"
    shown=$(printf '%s\n' "$kept" | wc -l | tr -d ' ')
  fi
  if [ "$total" -gt "$shown" ]; then echo "+$((total - shown)) more"; fi
  echo "stashes: $(git stash list 2>/dev/null | wc -l | tr -d ' ') | worktrees: $(git worktree list 2>/dev/null | wc -l | tr -d ' ')"
  echo "every path above changed before this session started, so another agent owns it"
  echo "do not stage, revert, reformat or commit one; if your work needs it, say so and stop"
}

TREE=$(working_tree)

jq -n --arg ctx "## working tree

$TREE" \
  '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $ctx}}'

exit 0

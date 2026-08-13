#!/bin/bash
# =============================================================
# @file inject-changes.sh - dirty paths and owners into context
# =============================================================
# @description
# - fires at session start: injects the working tree snapshot under a `## working tree` heading
# - prints the branch, every dirty path with a coarse age, then the stash and worktree counts
# - a session that has written nothing owns none of these paths, so each one is another agent's
# - closes on the directive naming who owns the paths, which is what stops a foreign revert
# - capped at 20 rows with a +N more tail, so a huge tree cannot spend the whole payload budget
# - anchors to the project root first, so the snapshot reads the repo rather than a subdirectory
# - self-contained on purpose: a manual install copies this one file and registers it
# @see plugins/operator/hooks/hooks.json, plugins/gitgud/skills/deliver/SKILL.md

command -v jq >/dev/null 2>&1 || exit 0

# hooks inherit the session's cwd, so anchor first; every path below stays relative to the root
cd "${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}" || exit 0

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

jq -n --arg ctx "## working tree

$TREE" \
  '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $ctx}}'

exit 0

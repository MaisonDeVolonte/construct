#!/bin/bash
# ==========================================================
# @file inject-readme.sh - the readme into opening context
# ==========================================================
# @description
# - fires at session start: injects README.md into the opening context
# - the harness caps one hook payload at 10000 characters and truncates the rest to a 2KB preview
# - the budget keeps this payload under that cap, so what is injected actually reaches context
# - the cut lands on a line boundary and is announced, with the path to read for the rest
# - a missing readme injects nothing, so a repo without one pays nothing
# - anchors to the project root first, so a subdirectory cwd resolves the same file
# - self-contained on purpose: a manual install copies this one file and registers it
# @see plugins/operator/hooks/hooks.json, README.md

command -v jq >/dev/null 2>&1 || exit 0

# hooks inherit the session's cwd, so anchor first; every path below stays relative to the root
cd "${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}" || exit 0

READ_ME="README.md"
# the 10000-char harness cap, minus headroom for the truncation notice appended below
PAYLOAD_BUDGET=9500

[ -f "$READ_ME" ] || exit 0

SIZE=$(wc -c < "$READ_ME" | tr -d ' ')
if [ "$SIZE" -le "$PAYLOAD_BUDGET" ]; then
  BODY=$(cat "$READ_ME")
else
  # a byte cut would land mid-line; stopping at the last whole line keeps the tail legible
  BODY=$(awk -v budget="$PAYLOAD_BUDGET" '{ used += length($0) + 1; if (used > budget) exit; print }' "$READ_ME")
  BODY="$BODY

[truncated: the first $PAYLOAD_BUDGET of $SIZE bytes; read $READ_ME for the rest]"
fi

jq -n --arg ctx "$BODY" \
  '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $ctx}}'

exit 0

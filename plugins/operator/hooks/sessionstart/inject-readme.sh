#!/bin/bash
# ==========================================================
# @file inject-readme.sh - the readme into opening context
# ==========================================================
# @description
# - fires at session start: injects README.md into the opening context
# - the harness caps one hook payload at 10000 characters and truncates the rest to a 2KB preview
# - the budget is spent against the SERIALIZED payload, since that is what the harness measures
# - json escaping sits between the body and stdout, so a body-only budget is a guess (see #1)
# - lengths are counted in characters, never bytes, since the cap counts characters (see #2)
# - the cut lands on a line boundary, and the notice names the sections it left behind
# - a missing readme injects nothing, so a repo without one pays nothing
# - anchors to the project root first, so a subdirectory cwd resolves the same file
# - self-contained on purpose: a manual install copies this one file and registers it
# - #1: whether the cap reads stdout or the extracted context is unproven, so stdout is the target
# - #2: `awk` counts bytes here, so a box-drawing readme spent ~500 chars of budget on nothing
# @see plugins/operator/hooks/hooks.json, plugins/operator/skills/context/SKILL.md, README.md

command -v jq >/dev/null 2>&1 || exit 0

# hooks inherit the session's cwd, so anchor first; every path below stays relative to the root
cd "${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}" || exit 0

READ_ME="README.md"
[ -f "$READ_ME" ] || exit 0

# the harness cap, held back a little because the exact boundary it measures is not documented
STDOUT_CAP=10000
HEADROOM=100
TARGET=$((STDOUT_CAP - HEADROOM))
# where the fit starts; it only ever shrinks from here, and one pass is the normal case
PAYLOAD_BUDGET=9500

# whole lines up to a character budget, so the tail stays legible and no line is cut mid-word
take_lines() {
  local budget=$1 body='' used=0 line len
  while IFS= read -r line; do
    len=$(( ${#line} + 1 ))
    if [ $((used + len)) -gt "$budget" ]; then break; fi
    used=$((used + len))
    body="$body$line"$'\n'
  done < "$READ_ME"
  printf '%s' "$body"
}

# the top-level sections the cut left behind: a map of what to go read beats "there is more"
dropped_sections() {
  awk -v skip="$1" 'NR > skip && /^## / { sub(/^## /, ""); printf "%s%s", sep, $0; sep = ", " }' "$READ_ME"
}

WHOLE=$(cat "$READ_ME")
SIZE=${#WHOLE}

# shrink until the serialized payload fits; the first pass carries it unless escaping is unusual
for _ in 1 2 3; do
  if [ "$SIZE" -le "$PAYLOAD_BUDGET" ]; then
    BODY=$WHOLE
  else
    BODY=$(take_lines "$PAYLOAD_BUDGET")
    LINES=$(printf '%s' "$BODY" | wc -l | tr -d ' ')
    BODY="$BODY
[truncated: ${#BODY} of $SIZE chars; read $READ_ME for the rest. it also covers: $(dropped_sections "$LINES")]"
  fi
  PAYLOAD=$(jq -n --arg ctx "$BODY" \
    '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $ctx}}')
  if [ ${#PAYLOAD} -le "$TARGET" ]; then break; fi
  # overshoot comes off the budget directly, plus a little, so the next pass lands under it
  PAYLOAD_BUDGET=$(( PAYLOAD_BUDGET - (${#PAYLOAD} - TARGET) - 20 ))
done

printf '%s\n' "$PAYLOAD"

exit 0

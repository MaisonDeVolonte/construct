#!/bin/bash
# ========================================================
# @file append-log.sh - blocks until a note is logged
# ========================================================
# @description
# - fires when a task completes: blocks the turn until a note lands in today's log
# - the note follows the `/retardify:log` template rather than inventing a shape
# - named demand rather than append, since the agent is what writes; this file only asks
# - a missing log file is treated as nothing, since the sessionstart action owns the stub (see #1)
# - works with any harness that can read files and follow instructions
# - anchors to the project root first, since a subdirectory cwd would name a stray log
# - #1: inject-log.sh stubs today's file at session start, so a missing one means no log protocol
# @see plugins/retardify/skills/log/SKILL.md, plugins/operator/hooks/hooks.json, .construct/retardify/log/

command -v jq >/dev/null 2>&1 || exit 0

# hooks inherit the session's cwd, so anchor first; every path below stays relative to the root
cd "${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}" || exit 0

TODAYS_LOG=".construct/retardify/log/$(date +%Y-%m-%d).md"

# a missing file means the log protocol is not in play here, so there is nothing to demand
[ -f "$TODAYS_LOG" ] || exit 0

jq -n --arg reason "add a note to $TODAYS_LOG (see /retardify:log); notify user" \
  '{decision:"block", reason:$reason}'

exit 0

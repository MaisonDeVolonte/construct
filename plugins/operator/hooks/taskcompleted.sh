#!/bin/bash
# ==================================================
# @file taskcompleted.sh - taskcompleted hook script
# ==================================================
# @description
# - creates today's log file if none exists yet
# - asks agent to add a note following the `/retardify:log` template
# - named as an invocation, since after an install a cross-plugin path resolves to nothing
# - works with any harness that can read files and follow instructions
# - anchors to the project root first, since a subdirectory cwd stubs a stray log and asks about it
# @see plugins/retardify/skills/log/SKILL.md, .construct/retardify/log/

# hooks inherit the session's cwd, so anchor first; every path below stays relative to the root
cd "${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}" || exit 0

# make today's log file if one doesn't exist
TODAYS_LOG=".construct/retardify/log/$(date +%Y-%m-%d).md"
if [ ! -f "$TODAYS_LOG" ];
then mkdir -p .construct/retardify/log; echo "# $TODAYS_LOG" > "$TODAYS_LOG"; fi

jq -n --arg reason "add a note to $TODAYS_LOG (see /retardify:log); notify user" \
  '{decision:"block", reason:$reason}'

exit 0

#!/bin/bash
# ==============================================
# @file taskcreated.sh - taskcreated hook script
# ==============================================
# @description
# - fires on TaskCreated (a TaskCreate call registers a new task)
# - decision:"block" prevents the creation itself here, unlike TaskCompleted
# - confirmed live: a blocked test task never got created, so this uses additionalContext
# - creates today's log file if missing
# - nudges the agent to check thread-relatedness, not enforced
# - anchors to the project root first, since a subdirectory cwd stubs a stray log and names it
# @see plugins/retardify/skills/log/SKILL.md, plugins/operator/hooks/taskcompleted.sh, .construct/retardify/log/

# hooks inherit the session's cwd, so anchor first; every path below stays relative to the root
cd "${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}" || exit 0

TODAYS_LOG=".construct/retardify/log/$(date +%Y-%m-%d).md"

# make today's log file if one doesn't exist
if [ ! -f "$TODAYS_LOG" ];
then mkdir -p .construct/retardify/log; echo "# $TODAYS_LOG" > "$TODAYS_LOG"; fi

jq -n --arg ctx "check the most recent thread in $TODAYS_LOG; if this new task is unrelated to it, start a new thread before continuing (see /retardify:log)" \
  '{hookSpecificOutput: {hookEventName: "TaskCreated", additionalContext: $ctx}}'

exit 0

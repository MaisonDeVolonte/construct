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
# @see plugins/retardify/skills/log/SKILL.md, plugins/operator/hooks/taskcompleted.sh, .operator/logs/

TODAYS_LOG=".operator/logs/$(date +%Y-%m-%d).md"

# make today's log file if one doesn't exist
if [ ! -f "$TODAYS_LOG" ];
then mkdir -p .operator/logs; echo "# $TODAYS_LOG" > "$TODAYS_LOG"; fi

jq -n --arg ctx "check the most recent thread in $TODAYS_LOG; if this new task is unrelated to it, start a new thread before continuing (see /retardify:log)" \
  '{hookSpecificOutput: {hookEventName: "TaskCreated", additionalContext: $ctx}}'

exit 0

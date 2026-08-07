#!/bin/bash
# ==================================================
# @file taskcompleted.sh - taskcompleted hook script
# ==================================================
# @description
# - creates today's log file if none exists yet
# - asks agent to add a note following the plugins/retardify/skills/log/SKILL.md template
# - works with any harness that can read files and follow instructions
# @see plugins/retardify/skills/log/SKILL.md, .operator/logs/

# make today's log file if one doesn't exist
TODAYS_LOG=".operator/logs/$(date +%Y-%m-%d).md"
if [ ! -f "$TODAYS_LOG" ];
then mkdir -p .operator/logs; echo "# $TODAYS_LOG" > "$TODAYS_LOG"; fi

jq -n --arg reason "add a note to $TODAYS_LOG (see plugins/retardify/skills/log/SKILL.md); notify user" \
  '{decision:"block", reason:$reason}'

exit 0

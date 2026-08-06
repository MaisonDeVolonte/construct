#!/bin/bash
# ==================================================
# @file taskcompleted.sh - taskcompleted hook script
# ==================================================
# @description
# - creates today's log file if none exists yet
# - asks agent to add a note following the AGENTS/skills/doc-logs/SKILL.md template
# - works with any harness that can read files and follow instructions
# @see AGENTS.md, AGENTS/skills/doc-logs/SKILL.md, docs/logs/

# make today's log file if one doesn't exist
TODAYS_LOG="docs/logs/$(date +%Y-%m-%d).md"
if [ ! -f "$TODAYS_LOG" ];
then mkdir -p docs/logs; echo "# $TODAYS_LOG" > "$TODAYS_LOG"; fi

jq -n --arg reason "add a note to $TODAYS_LOG (see AGENTS/skills/doc-logs/SKILL.md); notify user" \
  '{decision:"block", reason:$reason}'

exit 0

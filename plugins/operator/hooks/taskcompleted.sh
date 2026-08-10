#!/bin/bash
# ==================================================
# @file taskcompleted.sh - taskcompleted hook script
# ==================================================
# @description
# - creates today's log file if none exists yet
# - asks agent to add a note following the `/retardify:log` template
# - named as an invocation, since after an install a cross-plugin path resolves to nothing
# - works with any harness that can read files and follow instructions
# @see plugins/retardify/skills/log/SKILL.md, .construct/retardify/log/

# make today's log file if one doesn't exist
TODAYS_LOG=".construct/retardify/log/$(date +%Y-%m-%d).md"
if [ ! -f "$TODAYS_LOG" ];
then mkdir -p .construct/retardify/log; echo "# $TODAYS_LOG" > "$TODAYS_LOG"; fi

jq -n --arg reason "add a note to $TODAYS_LOG (see /retardify:log); notify user" \
  '{decision:"block", reason:$reason}'

exit 0

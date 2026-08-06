#!/bin/bash
# ================================
# @file stop.sh - stop hook script
# ================================
# @description
# - creates today's log file if none exists yet
# - every hour: appends notes, flushes uncaptured prompts, and synthesizes the thread
# - one file means one mtime, so the interval timer measures every kind of write
# - works with `claude`; does not work with `grok`
# @see AGENTS.md, AGENTS/skills/doc-logs/SKILL.md, docs/logs/

TODAYS_LOG="docs/logs/$(date +%Y-%m-%d).md"
# seconds between runs
UPDATE_INTERVAL=3600
NOW=$(date +%s)
LAST_MODIFIED=$(stat -f %m "$TODAYS_LOG" 2>/dev/null || stat -c %Y "$TODAYS_LOG" 2>/dev/null || echo 0)

# make today's log file if one doesn't exist
if [ ! -f "$TODAYS_LOG" ];
then mkdir -p docs/logs; echo "# $TODAYS_LOG" > "$TODAYS_LOG"; fi

# check if today's log was updated recently
ELAPSED_TIME=$((NOW - LAST_MODIFIED))
if [ "$ELAPSED_TIME" -gt "$UPDATE_INTERVAL" ]; then

  NOTES_TASK="append notes to the end of $TODAYS_LOG (see AGENTS/skills/doc-logs/SKILL.md)"

  PROMPTS_TASK="append any uncaptured prompts to their thread's PROMPTS block in $TODAYS_LOG"

  SYNTHESIZE_TASK="synthesize $TODAYS_LOG (see AGENTS/skills/doc-logs/SKILL.md): incorporate notes \
  into thread prose, and prune each thread's prompts without turning them into prose"

  jq -n --arg reason "$NOTES_TASK; $PROMPTS_TASK; $SYNTHESIZE_TASK; notify user" \
  '{decision:"block", reason:$reason}'
  exit 0
fi

exit 0

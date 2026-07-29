#!/bin/bash
# ================================
# @file stop.sh - stop hook script
# ================================
# @description
# - creates today's log + prompts files if none exist yet
# - appends a note to a thread every 15 minutes
# - synthesizes notes into corresponding threads every hour
# - every tick also asks for any uncaptured prompts to be flushed
# - works with `claude`; does not work with `grok`
# @see AGENTS.md, AGENTS/templates/logs.md, AGENTS/templates/prompts.md, docs/logs/, docs/prompts/

TODAYS_LOG="docs/logs/$(date +%Y-%m-%d).md"
TODAYS_PROMPTS="docs/prompts/$(date +%Y-%m-%d).md"
UPDATE_INTERVAL=900
SYNTHESIZE_INTERVAL=4
# hook state, not an artifact — lives above the archives so it never lands in a dated file
TICKER_FILE="docs/.ticker"
NOW=$(date +%s)
LAST_MODIFIED=$(stat -f %m "$TODAYS_LOG" 2>/dev/null || stat -c %Y "$TODAYS_LOG" 2>/dev/null || echo 0)

# make today's log file if one doesn't exist
if [ ! -f "$TODAYS_LOG" ];
then mkdir -p docs/logs; echo "# $TODAYS_LOG" > "$TODAYS_LOG"; fi

# make today's prompts file if one doesn't exist
if [ ! -f "$TODAYS_PROMPTS" ];
then mkdir -p docs/prompts; echo "# $TODAYS_PROMPTS" > "$TODAYS_PROMPTS"; fi

# check if today's log was updated recently
ELAPSED_TIME=$((NOW - LAST_MODIFIED))
if [ "$ELAPSED_TIME" -gt "$UPDATE_INTERVAL" ]; then

  # this script runs fresh on every stop hook, so the tick count has to be persisted to disk
  TICKER_COUNT=$(cat "$TICKER_FILE" 2>/dev/null || echo 0)
  case "$TICKER_COUNT" in ''|*[!0-9]*) TICKER_COUNT=0 ;; esac
  TICKER_COUNT=$((TICKER_COUNT + 1))

  NOTES_TASK="append a note to the end of $TODAYS_LOG (see AGENTS/templates/logs.md)"

  PROMPTS_TASK="rewrite missing prompts to $TODAYS_PROMPTS (see AGENTS/templates/prompts.md)"

  SYNTHESIZE_TASK="synthesize notes from $TODAYS_LOG (see AGENTS/templates/logs.md) \
  and synthesize prompts from $TODAYS_PROMPTS (see AGENTS/templates/prompts.md)"

  # checks if ticker is on a synthesize interval
  if [ "$((TICKER_COUNT % SYNTHESIZE_INTERVAL))" -eq 0 ];
  # asks for synthesis and prompts
  then echo 0 > "$TICKER_FILE"
    jq -n --arg reason "$SYNTHESIZE_TASK; $PROMPTS_TASK; notify user" \
    '{decision:"block", reason:$reason}'
  # asks for notes and prompts
  else echo "$TICKER_COUNT" > "$TICKER_FILE"
    jq -n --arg reason "$NOTES_TASK; $PROMPTS_TASK; notify user" \
    '{decision:"block", reason:$reason}'
  fi
  exit 0
fi

exit 0

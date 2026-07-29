#!/bin/bash
# ================================
# @file stop.sh - stop hook script
# ================================
# @description
# - creates today's log file if none exists yet
# - appends a note to a thread every 15 minutes
# - synthesizes notes into corresponding threads every hour
# - every tick also asks for any uncaptured prompts to be flushed into their thread
# - one file means one mtime, so the interval timer measures every kind of write
# - works with `claude`; does not work with `grok`
# @see AGENTS.md, AGENTS/templates/logs.md, docs/logs/

TODAYS_LOG="docs/logs/$(date +%Y-%m-%d).md"
UPDATE_INTERVAL=900
SYNTHESIZE_INTERVAL=4
# hook state, not an artifact — lives above the archives so it never lands in a dated file
TICKER_FILE="docs/.ticker"
NOW=$(date +%s)
LAST_MODIFIED=$(stat -f %m "$TODAYS_LOG" 2>/dev/null || stat -c %Y "$TODAYS_LOG" 2>/dev/null || echo 0)

# make today's log file if one doesn't exist
if [ ! -f "$TODAYS_LOG" ];
then mkdir -p docs/logs; echo "# $TODAYS_LOG" > "$TODAYS_LOG"; fi

# check if today's log was updated recently
ELAPSED_TIME=$((NOW - LAST_MODIFIED))
if [ "$ELAPSED_TIME" -gt "$UPDATE_INTERVAL" ]; then

  # this script runs fresh on every stop hook, so the tick count has to be persisted to disk
  TICKER_COUNT=$(cat "$TICKER_FILE" 2>/dev/null || echo 0)
  case "$TICKER_COUNT" in ''|*[!0-9]*) TICKER_COUNT=0 ;; esac
  TICKER_COUNT=$((TICKER_COUNT + 1))

  NOTES_TASK="append a note to the end of $TODAYS_LOG (see AGENTS/templates/logs.md)"

  PROMPTS_TASK="append any uncaptured prompts to their thread's PROMPTS block in $TODAYS_LOG"

  SYNTHESIZE_TASK="synthesize $TODAYS_LOG (see AGENTS/templates/logs.md): incorporate notes \
  into thread prose, and prune each thread's prompts without turning them into prose"

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

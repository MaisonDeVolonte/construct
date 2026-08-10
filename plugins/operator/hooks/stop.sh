#!/bin/bash
# ================================
# @file stop.sh - stop hook script
# ================================
# @description
# - creates today's log file if none exists yet
# - asks for a synthesis whenever the log is carrying work the next session would pay for
# - the cheap check is state, not time: pending notes and oversized threads are both greppable
# - state clears when the agent does the work, so the ask stops on its own rather than on a clock
# - the hourly pass stays for what no grep can see, which is a prompt that was never captured
# - a debounce keeps a stubborn thread from asking again before the agent has had a turn
# - works with `claude`; does not work with `grok`
# @see plugins/retardify/skills/log/SKILL.md, plugins/operator/hooks/taskcompleted.sh, .construct/retardify/log/

TODAYS_LOG=".construct/retardify/log/$(date +%Y-%m-%d).md"

# seconds between full passes, which is the backstop rather than the main trigger
UPDATE_INTERVAL=3600
# seconds of grace after any log write, so a synthesis is never demanded twice in a row
SYNTH_DEBOUNCE=300

NOW=$(date +%s)
LAST_MODIFIED=$(stat -f %m "$TODAYS_LOG" 2>/dev/null || stat -c %Y "$TODAYS_LOG" 2>/dev/null || echo 0)

# make today's log file if one doesn't exist
if [ ! -f "$TODAYS_LOG" ];
then mkdir -p .construct/retardify/log; echo "# $TODAYS_LOG" > "$TODAYS_LOG"; fi

ELAPSED_TIME=$((NOW - LAST_MODIFIED))

NOTES_TASK="append notes to the end of $TODAYS_LOG (see /retardify:log)"
PROMPTS_TASK="append any uncaptured prompts to their thread's PROMPTS block in $TODAYS_LOG"
SYNTHESIZE_TASK="synthesize $TODAYS_LOG (see /retardify:log): incorporate notes \
into thread prose, and prune each thread's prompts without turning them into prose"

# the full pass first, since it covers everything the cheap check does and more
if [ "$ELAPSED_TIME" -gt "$UPDATE_INTERVAL" ]; then
  jq -n --arg reason "$NOTES_TASK; $PROMPTS_TASK; $SYNTHESIZE_TASK; notify user" \
    '{decision:"block", reason:$reason}'
  exit 0
fi

# the cheap check: the log skill owns the byte cap, so ask rather than keep a second copy
LOG_SKILL="$(dirname "${BASH_SOURCE[0]}")/../../retardify/skills/log/log.sh"
THREAD_MAX_BYTES=$(bash "$LOG_SKILL" --budget 2>/dev/null | sed -n 's/^thread_max_bytes: //p')
THREAD_MAX_BYTES=${THREAD_MAX_BYTES:-5000}

# a note the agent left for itself is work the next reader inherits, and it is one grep away
# `|| true` rather than `|| echo 0`: grep -c already prints 0 and then exits 1, so echoing a
# second 0 makes the count "0\n0" and every numeric test after it fails open
PENDING_NOTES=$(grep -c '^#### NOTE:' "$TODAYS_LOG" 2>/dev/null || true)
PENDING_NOTES=${PENDING_NOTES:-0}

# a thread past the byte cap is context the next session cannot afford, since sessionstart now
# injects whole threads rather than truncating; the widest one is what the ask names
WIDEST=$(awk -v cap="$THREAD_MAX_BYTES" '
  /^## Thread #/ { if (n) { if (b > max) { max = b; name = h } } h = $0; b = 0; n = 1 }
  n { b += length($0) + 1 }
  END { if (n && b > max) { max = b; name = h }; if (max > cap) print max "\t" name }
' "$TODAYS_LOG" 2>/dev/null)

if [ "$PENDING_NOTES" -eq 0 ] && [ -z "$WIDEST" ]; then exit 0; fi

# the debounce is the only thing standing between a stubborn thread and an ask on every turn
if [ "$ELAPSED_TIME" -lt "$SYNTH_DEBOUNCE" ]; then exit 0; fi

REASON="synthesize $TODAYS_LOG (see /retardify:log)"
if [ "$PENDING_NOTES" -gt 0 ]; then
  REASON="$REASON: incorporate the $PENDING_NOTES pending note(s) into thread prose and delete them"
fi
if [ -n "$WIDEST" ]; then
  REASON="$REASON: $(printf '%s' "$WIDEST" | cut -f2) is $(printf '%s' "$WIDEST" | cut -f1) bytes \
against a $THREAD_MAX_BYTES cap, so tighten its prose or split it"
fi
jq -n --arg reason "$REASON; notify user" '{decision:"block", reason:$reason}'
exit 0

#!/bin/bash
# ====================================================================
# @file synthesize-log.sh - blocks a turn on an unsynthesized log
# ====================================================================
# @description
# - fires when a turn tries to end: asks for a synthesis when the log carries pending work
# - the cheap check is state, not time: pending notes and oversized threads are both greppable
# - state clears when the agent does the work, so the ask stops on its own rather than on a clock
# - the hourly pass stays for what no grep can see, which is a prompt that was never captured
# - a debounce keeps a stubborn thread from asking again before the agent has had a turn
# - a missing log file is treated as nothing, since the sessionstart action owns the stub (see #1)
# - named demand rather than synthesize, since the agent is what writes; this file only asks
# - anchors to the project root first, since a subdirectory cwd would read a stray log
# - #1: a missing file used to read as infinitely stale and demand a full pass on a fresh project
# @see plugins/operator/skills/logs/SKILL.md, plugins/operator/hooks/hooks.json, plugins/operator/hooks/stop/retardify-output.sh

# hooks inherit the session's cwd, so anchor first; every path below stays relative to the root
cd "${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}" || exit 0

command -v jq >/dev/null 2>&1 || exit 0

TODAYS_LOG=".construct/operator/logs/$(date +%Y-%m-%d).md"

# seconds between full passes, which is the backstop rather than the main trigger
UPDATE_INTERVAL=3600
# seconds of grace after any log write, so a synthesis is never demanded twice in a row
SYNTH_DEBOUNCE=300

# a missing file means the log protocol is not in play here, so there is nothing to demand (see #1)
[ -f "$TODAYS_LOG" ] || exit 0

NOW=$(date +%s)
LAST_MODIFIED=$(stat -f %m "$TODAYS_LOG" 2>/dev/null || stat -c %Y "$TODAYS_LOG" 2>/dev/null || echo "$NOW")
ELAPSED_TIME=$((NOW - LAST_MODIFIED))

NOTES_TASK="append notes to the end of $TODAYS_LOG (see /operator:logs)"
PROMPTS_TASK="append any uncaptured prompts to their thread's PROMPTS block in $TODAYS_LOG"
SYNTHESIZE_TASK="synthesize $TODAYS_LOG (see /operator:logs): incorporate notes \
into thread prose, and prune each thread's prompts without turning them into prose"

REASON=''

# the full pass first, since it covers everything the cheap check does and more
if [ "$ELAPSED_TIME" -gt "$UPDATE_INTERVAL" ]; then
  REASON="$NOTES_TASK; $PROMPTS_TASK; $SYNTHESIZE_TASK"
else
  # the cheap check: the logs skill owns the byte cap, so ask rather than keep a second copy
  LOG_SKILL="$(dirname "${BASH_SOURCE[0]}")/../../skills/logs/logs.sh"
  THREAD_MAX_BYTES=$(bash "$LOG_SKILL" --budget 2>/dev/null | sed -n 's/^thread_max_bytes: //p')
  THREAD_MAX_BYTES=${THREAD_MAX_BYTES:-5000}

  # a note the agent left for itself is work the next reader inherits, and it is one grep away
  # `|| true` rather than `|| echo 0`: grep -c already prints 0 and then exits 1, so echoing a
  # second 0 makes the count "0\n0" and every numeric test after it fails open
  PENDING_NOTES=$(grep -c '^#### NOTE:' "$TODAYS_LOG" 2>/dev/null || true)
  PENDING_NOTES=${PENDING_NOTES:-0}

  # a thread past the byte cap is context the next session cannot afford, since the sessionstart
  # actions inject whole threads rather than truncating; the widest one is what the ask names
  WIDEST=$(awk -v cap="$THREAD_MAX_BYTES" '
    /^## Thread #/ { if (n) { if (b > max) { max = b; name = h } } h = $0; b = 0; n = 1 }
    n { b += length($0) + 1 }
    END { if (n && b > max) { max = b; name = h }; if (max > cap) print max "\t" name }
  ' "$TODAYS_LOG" 2>/dev/null)

  # the debounce is the only thing standing between a stubborn thread and an ask on every turn
  if { [ "$PENDING_NOTES" -gt 0 ] || [ -n "$WIDEST" ]; } \
    && [ "$ELAPSED_TIME" -ge "$SYNTH_DEBOUNCE" ]; then
    REASON="synthesize $TODAYS_LOG (see /operator:logs)"
    if [ "$PENDING_NOTES" -gt 0 ]; then
      REASON="$REASON: incorporate the $PENDING_NOTES pending note(s) into thread prose \
and delete them"
    fi
    if [ -n "$WIDEST" ]; then
      REASON="$REASON: $(printf '%s' "$WIDEST" | cut -f2) is \
$(printf '%s' "$WIDEST" | cut -f1) bytes against a $THREAD_MAX_BYTES cap, so tighten it or split it"
    fi
  fi
fi

if [ -z "$REASON" ]; then exit 0; fi

jq -n --arg reason "$REASON; notify user" '{decision:"block", reason:$reason}'
exit 0

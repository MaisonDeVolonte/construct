#!/bin/bash
# ================================
# @file stop.sh - stop hook script
# ================================
# @description
# STYLE
# - grades a recent reply against the Output Style spec, since no other gate ever reads one
# - `shared/style.sh` owns the rules; this file only extracts the text and merges the ask
# - the transcript may not hold the current reply yet, so findings can describe the turn before
# ESCAPE
# - `.construct/operator/style/off` disables the gate outright; delete it to re-enable
# - a streak of STREAK_LIMIT consecutive style blocks trips a breaker and stops the asking
# - the breaker resets on the first clean reply, so it costs nothing once the rules settle
# - without both, a rule nobody predicted can hold a session hostage with no way out
# LOG
# - creates today's log file if none exists yet
# - asks for a synthesis whenever the log is carrying work the next session would pay for
# - the cheap check is state, not time: pending notes and oversized threads are both greppable
# - state clears when the agent does the work, so the ask stops on its own rather than on a clock
# - the hourly pass stays for what no grep can see, which is a prompt that was never captured
# - a debounce keeps a stubborn thread from asking again before the agent has had a turn
# - works with `claude`; does not work with `grok`
# - anchors to the project root first, since a subdirectory cwd stubs a stray log and asks about it
# @see plugins/operator/shared/style.sh, plugins/retardify/skills/log/SKILL.md, .construct/retardify/log/

# hooks inherit the session's cwd, so anchor first; every path below stays relative to the root
cd "${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}" || exit 0

TODAYS_LOG=".construct/retardify/log/$(date +%Y-%m-%d).md"

# seconds between full passes, which is the backstop rather than the main trigger
UPDATE_INTERVAL=3600
# seconds of grace after any log write, so a synthesis is never demanded twice in a row
SYNTH_DEBOUNCE=300
# consecutive style blocks before the gate gives up; three is a pattern rather than a bad turn
STREAK_LIMIT=3

STYLE_DIR=".construct/operator/style"
STYLE_OFF="$STYLE_DIR/off"
STAMP="$STYLE_DIR/last-blocked"
STREAK="$STYLE_DIR/streak"

NOW=$(date +%s)
LAST_MODIFIED=$(stat -f %m "$TODAYS_LOG" 2>/dev/null || stat -c %Y "$TODAYS_LOG" 2>/dev/null || echo 0)

# make today's log file if one doesn't exist
if [ ! -f "$TODAYS_LOG" ];
then mkdir -p .construct/retardify/log; echo "# $TODAYS_LOG" > "$TODAYS_LOG"; fi

ELAPSED_TIME=$((NOW - LAST_MODIFIED))

# ==============
# STYLE
# ==============
STYLE_REASON=''
# the env override exists so this file can be exercised from outside its own directory; without it
# the sibling path resolves against wherever a copy sits and the gate silently never runs
STYLE_LINT="${OPERATOR_STYLE_LINT:-$(dirname "${BASH_SOURCE[0]}")/../shared/style.sh}"
HOOK_INPUT=''
# a tty means somebody ran this by hand, and reading stdin there would hang waiting on a human
if [ ! -t 0 ]; then HOOK_INPUT=$(cat 2>/dev/null || true); fi
TRANSCRIPT=$(printf '%s' "$HOOK_INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)

COUNT=$(cat "$STREAK" 2>/dev/null || echo 0)
case "$COUNT" in ''|*[!0-9]*) COUNT=0;; esac

if [ -f "$STYLE_OFF" ]; then STYLE_LINT=''; fi
if [ "$COUNT" -ge "$STREAK_LIMIT" ]; then STYLE_LINT=''; fi

if [ -n "$STYLE_LINT" ] && [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ] && [ -f "$STYLE_LINT" ]; then
  # the LAST assistant turn carrying text, its parts joined; slurping is what lets `last` pick one
  REPLY_TEXT=$(jq -rs '[.[] | select(.type=="assistant")
      | [.message.content[]? | select(.type=="text") | .text]
      | join("\n") | select(length > 0)] | last // ""' "$TRANSCRIPT" 2>/dev/null)

  if [ -n "$REPLY_TEXT" ]; then
    SEEN=$(cat "$STAMP" 2>/dev/null || true)
    HASH=$(printf '%s' "$REPLY_TEXT" | md5 -q 2>/dev/null \
      || printf '%s' "$REPLY_TEXT" | md5sum 2>/dev/null | cut -d' ' -f1)
    if [ "$SEEN" != "$HASH" ]; then
      mkdir -p "$STYLE_DIR"
      if FINDINGS=$(printf '%s' "$REPLY_TEXT" | bash "$STYLE_LINT" - 2>/dev/null); then
        # a clean reply is what the breaker is waiting for, so the streak dies here
        printf '0' > "$STREAK"
      else
        COUNT=$((COUNT + 1))
        printf '%s' "$COUNT" > "$STREAK"
        printf '%s' "$HASH" > "$STAMP"
        STYLE_REASON="a recent reply broke the output style, possibly the one before the last, \
since the transcript lags; fix these and move on rather than restating twice: $FINDINGS"
        if [ "$COUNT" -ge "$STREAK_LIMIT" ]; then
          STYLE_REASON="$STYLE_REASON; that was style block $COUNT of $STREAK_LIMIT, \
so the gate is now off until a clean reply resets it"
        fi
      fi
    fi
  fi
fi

# ==============
# LOG
# ==============
NOTES_TASK="append notes to the end of $TODAYS_LOG (see /retardify:log)"
PROMPTS_TASK="append any uncaptured prompts to their thread's PROMPTS block in $TODAYS_LOG"
SYNTHESIZE_TASK="synthesize $TODAYS_LOG (see /retardify:log): incorporate notes \
into thread prose, and prune each thread's prompts without turning them into prose"

LOG_REASON=''

# the full pass first, since it covers everything the cheap check does and more
if [ "$ELAPSED_TIME" -gt "$UPDATE_INTERVAL" ]; then
  LOG_REASON="$NOTES_TASK; $PROMPTS_TASK; $SYNTHESIZE_TASK"
else
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

  # the debounce is the only thing standing between a stubborn thread and an ask on every turn
  if { [ "$PENDING_NOTES" -gt 0 ] || [ -n "$WIDEST" ]; } \
    && [ "$ELAPSED_TIME" -ge "$SYNTH_DEBOUNCE" ]; then
    LOG_REASON="synthesize $TODAYS_LOG (see /retardify:log)"
    if [ "$PENDING_NOTES" -gt 0 ]; then
      LOG_REASON="$LOG_REASON: incorporate the $PENDING_NOTES pending note(s) into thread prose \
and delete them"
    fi
    if [ -n "$WIDEST" ]; then
      LOG_REASON="$LOG_REASON: $(printf '%s' "$WIDEST" | cut -f2) is \
$(printf '%s' "$WIDEST" | cut -f1) bytes against a $THREAD_MAX_BYTES cap, so tighten it or split it"
    fi
  fi
fi

# ==============
# DECIDE
# ==============
if [ -z "$STYLE_REASON" ] && [ -z "$LOG_REASON" ]; then exit 0; fi

# style first: the reply is what the user is reading right now, the log is housekeeping after it
REASON="$STYLE_REASON"
if [ -n "$REASON" ] && [ -n "$LOG_REASON" ]; then REASON="$REASON; then $LOG_REASON"
elif [ -z "$REASON" ]; then REASON="$LOG_REASON"; fi

jq -n --arg reason "$REASON; notify user" '{decision:"block", reason:$reason}'
exit 0

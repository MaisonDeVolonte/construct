#!/bin/bash
# ========================================================
# @file retardify-output.sh - grades the reply at turn end
# ========================================================
# @description
# - fires when a turn tries to end: grades the last reply through the `/retardify:output` linter
# - blocks the turn on hard findings, so the reply the user reads is the one that conforms
# - `.construct/operator/style/off` disables the gate outright; delete the file to re-enable
# - a clean reply resets a running streak; 3 consecutive blocks trip a breaker that stays off
# - a tripped breaker skips grading entirely, so re-arming means resetting the streak file to 0
# - a reply is graded once; a hash stamp keeps a repeated transcript from blocking twice
# - the transcript may lag a turn, so findings can describe the reply before the last
# - degrades to one stderr line when the retardify plugin is not installed beside operator
# - anchors to the project root first, so the escape files resolve at the repo rather than a cwd
# @see plugins/retardify/skills/output/, plugins/operator/hooks/hooks.json, plugins/operator/hooks/stop/synthesize-log.sh

# hooks inherit the session's cwd, so anchor first; every path below stays relative to the root
cd "${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}" || exit 0

command -v jq >/dev/null 2>&1 || exit 0

# consecutive style blocks before the gate gives up; three is a pattern rather than a bad turn
STREAK_LIMIT=3

STYLE_DIR=".construct/operator/style"
STYLE_OFF="$STYLE_DIR/off"
STAMP="$STYLE_DIR/last-blocked"
STREAK="$STYLE_DIR/streak"

# the linter is a retardify skill sidecar, resolved beside this plugin like the posttooluse actions
LINT="$(dirname "${BASH_SOURCE[0]}")/../../../retardify/skills/output/output.sh"
if [ ! -f "$LINT" ]; then
  echo "retardify-output: no retardify/skills beside this hook; the style gate is off" >&2
  exit 0
fi

[ -f "$STYLE_OFF" ] && exit 0

COUNT=$(cat "$STREAK" 2>/dev/null || echo 0)
case "$COUNT" in ''|*[!0-9]*) COUNT=0;; esac
[ "$COUNT" -ge "$STREAK_LIMIT" ] && exit 0

# a tty means somebody ran this by hand, and reading stdin there would hang waiting on a human
HOOK_INPUT=''
if [ ! -t 0 ]; then HOOK_INPUT=$(cat 2>/dev/null || true); fi
TRANSCRIPT=$(printf '%s' "$HOOK_INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
if [ -z "$TRANSCRIPT" ] || [ ! -f "$TRANSCRIPT" ]; then exit 0; fi

# the LAST assistant turn carrying text, its parts joined; slurping is what lets `last` pick one
REPLY_TEXT=$(jq -rs '[.[] | select(.type=="assistant")
    | [.message.content[]? | select(.type=="text") | .text]
    | join("\n") | select(length > 0)] | last // ""' "$TRANSCRIPT" 2>/dev/null)
[ -n "$REPLY_TEXT" ] || exit 0

# a reply already judged never blocks twice, whatever the verdict was the first time
SEEN=$(cat "$STAMP" 2>/dev/null || true)
HASH=$(printf '%s' "$REPLY_TEXT" | md5 -q 2>/dev/null \
  || printf '%s' "$REPLY_TEXT" | md5sum 2>/dev/null | cut -d' ' -f1)
[ "$SEEN" = "$HASH" ] && exit 0

mkdir -p "$STYLE_DIR"
if FINDINGS=$(printf '%s' "$REPLY_TEXT" | bash "$LINT" - 2>/dev/null); then
  # a clean reply is what the breaker is waiting for, so the streak dies here
  printf '0' > "$STREAK"
  exit 0
fi

COUNT=$((COUNT + 1))
printf '%s' "$COUNT" > "$STREAK"
printf '%s' "$HASH" > "$STAMP"
REASON="a recent reply broke the output style, possibly the one before the last, \
since the transcript lags; fix these and move on rather than restating twice: $FINDINGS"
if [ "$COUNT" -ge "$STREAK_LIMIT" ]; then
  REASON="$REASON; that was style block $COUNT of $STREAK_LIMIT, \
so the gate is now off until a clean reply resets it"
fi

jq -n --arg reason "$REASON; notify user" '{decision:"block", reason:$reason}'
exit 0

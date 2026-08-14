#!/bin/bash
# ========================================================
# @file retardify-output.sh - grades the reply at turn end
# ========================================================
# @description
# - fires when a turn tries to end: grades the last reply through the `/retardify:output` linter
# - blocks the turn on hard findings, so the reply the user reads is the one that conforms
# - `.construct/operator/style/off` disables the gate outright; delete the file to re-enable
# - grades only the reply that ends the turn, which is the transcript's last main-chain message
# - a transcript still mid-turn is skipped rather than graded, since the reply is not written yet
# - a sidechain reply is skipped too, because a subagent's text never reaches the user
# - a reply is graded once; a hash stamp keeps a repeated transcript from blocking twice
# - blocks are capped per session under $TMPDIR, so the cap expires and never needs a hand reset
# - every reply is graded even past the cap, so a clean one always clears the count
# - degrades to one stderr line when the retardify plugin is not installed beside operator
# - anchors to the project root first, so the escape files resolve at the repo rather than a cwd
# @see plugins/retardify/skills/output/, plugins/operator/hooks/hooks.json, plugins/operator/hooks/stop/synthesize-log.sh

# hooks inherit the session's cwd, so anchor first; every path below stays relative to the root
cd "${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}" || exit 0

command -v jq >/dev/null 2>&1 || exit 0

# blocks allowed in one session before the gate stands down; the count dies with the session, so
# this bounds a runaway inside one conversation rather than latching across every future one
ATTEMPT_LIMIT=3

STYLE_DIR=".construct/operator/style"
STYLE_OFF="$STYLE_DIR/off"

# the linter is a retardify skill sidecar, resolved beside this plugin like the posttooluse actions
LINT="$(dirname "${BASH_SOURCE[0]}")/../../../retardify/skills/output/output.sh"
if [ ! -f "$LINT" ]; then
  echo "retardify-output: no retardify/skills beside this hook; the style gate is off" >&2
  exit 0
fi

[ -f "$STYLE_OFF" ] && exit 0

# a tty means somebody ran this by hand, and reading stdin there would hang waiting on a human
HOOK_INPUT=''
if [ ! -t 0 ]; then HOOK_INPUT=$(cat 2>/dev/null || true); fi
TRANSCRIPT=$(printf '%s' "$HOOK_INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
if [ -z "$TRANSCRIPT" ] || [ ! -f "$TRANSCRIPT" ]; then exit 0; fi

# session state lives in the scratch dir, which is cleanable by design; nothing here outlives the
# conversation it bounds, which is why re-arming the gate is never a task somebody has to remember
SESSION=$(printf '%s' "$HOOK_INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null)
case "$SESSION" in ''|*[!a-zA-Z0-9_-]*) SESSION=unknown;; esac
STATE_DIR="${TMPDIR:-/tmp}/retardify-output"
STAMP="$STATE_DIR/$SESSION.hash"
ATTEMPTS="$STATE_DIR/$SESSION.count"

COUNT=$(cat "$ATTEMPTS" 2>/dev/null || echo 0)
case "$COUNT" in ''|*[!0-9]*) COUNT=0;; esac

# anything sitting after the last assistant text means this turn's reply is not written yet, and
# grading the previous one is what made the agent rewrite text it could no longer see
REPLY_TEXT=$(jq -rs '
  [ .[]
    | select(.isSidechain != true)
    | select(.type == "user" or .type == "assistant")
  ] | last as $tail
  | if ($tail.type == "assistant")
    then [ $tail.message.content[]? | select(.type == "text") | .text ] | join("\n")
    else "" end' "$TRANSCRIPT" 2>/dev/null)
[ -n "$REPLY_TEXT" ] || exit 0

# a reply already judged never blocks twice, whatever the verdict was the first time
SEEN=$(cat "$STAMP" 2>/dev/null || true)
HASH=$(printf '%s' "$REPLY_TEXT" | md5 -q 2>/dev/null \
  || printf '%s' "$REPLY_TEXT" | md5sum 2>/dev/null | cut -d' ' -f1)
[ "$SEEN" = "$HASH" ] && exit 0

mkdir -p "$STATE_DIR"
if FINDINGS=$(printf '%s' "$REPLY_TEXT" | bash "$LINT" - 2>/dev/null); then
  rm -f "$ATTEMPTS" 2>/dev/null
  exit 0
fi

COUNT=$((COUNT + 1))
printf '%s' "$COUNT" > "$ATTEMPTS"
printf '%s' "$HASH" > "$STAMP"

# grading always runs, so a clean reply above clears the count even after the cap was reached;
# only the block is withheld here, which is what keeps the stand-down from latching
[ "$COUNT" -gt "$ATTEMPT_LIMIT" ] && exit 0

REASON="this reply broke the output style; each finding quotes the line it read, \
so fix those lines and move on rather than restating the whole reply: $FINDINGS"
if [ "$COUNT" -ge "$ATTEMPT_LIMIT" ]; then
  REASON="$REASON; that was style block $COUNT of $ATTEMPT_LIMIT, \
so the next reply ends the turn whatever it reads, and a clean one re-arms the gate"
fi

jq -n --arg reason "$REASON; notify user" '{decision:"block", reason:$reason}'
exit 0

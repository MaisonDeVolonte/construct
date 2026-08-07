#!/bin/bash
# ==============================================
# @file posttooluse.sh - posttooluse hook script
# ==============================================
# @description
# - runs after Write|Edit succeeds
# - extracts the touched file path from claude or grok payloads
# - runs `eslint --fix` if it's a js/jsx/ts/tsx file
# - shapes comments and the wayfinding header through their two template sidecars
# - findings come back as context, never as a block: the write already landed
# - the agent fixes them on its next turn, which is where a style rule actually changes behaviour
# - silent when nothing is wrong, so a clean file costs one exit and no context
# @see AGENTS.md, plugins/retardify/skills/comments/, plugins/retardify/skills/wayfinders/, .claude/settings.json

# the sidecars report per finding, and a long file could bury the turn in style notes
MAX_FINDINGS=20

FILE=$(jq -r '
  .tool_response.filePath
  // .tool_response.file_path
  // .tool_input.file_path
  // .toolInput.file_path
  // .toolInput.path
  // empty
')

# a rename or a delete leaves a path that no longer resolves, and there is nothing to shape
if [ -z "$FILE" ] || [ ! -f "$FILE" ]; then exit 0; fi

case "$FILE" in
  *.js|*.jsx|*.ts|*.tsx) npx eslint --fix "$FILE" 2>/dev/null ;;
esac

# the validators live in the audit plugin, which sits beside this one in the same checkout
SKILLS=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../audit/skills" 2>/dev/null && pwd || true)
# a missing directory means a rename moved the validators, which would silently disable this hook
if [ ! -d "$SKILLS" ]; then
  echo "posttooluse: no audit/skills beside this hook; comment and wayfinder linting is off" >&2
  exit 0
fi

# both exit 1 on ERROR, which is right for a gate and wrong here: this hook never fails a write,
# so their exit codes are absorbed and only what they printed is passed along
FINDINGS=$(
  {
    bash "$SKILLS/comments/comments.sh" "$FILE" 2>/dev/null || true
    bash "$SKILLS/wayfinders/wayfinders.sh" "$FILE" 2>/dev/null || true
  } | grep -E '^(ERROR|WARN)[[:space:]]' | head -n "$MAX_FINDINGS" || true
)

if [ -z "$FINDINGS" ]; then exit 0; fi

jq -n --arg ctx "comment and wayfinder findings for $FILE (see /check-comments and
/check-wayfinders); fix the ERRORs, justify or fix the WARNs:
$FINDINGS" \
  '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $ctx}}'

exit 0

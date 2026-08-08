#!/bin/bash
# ==============================================
# @file posttooluse.sh - posttooluse hook script
# ==============================================
# @description
# - runs `eslint --fix` and `/retardify:file` after a successful Write|Edit
# - findings come back as context, agent fixes them on its next turn
# - silent when nothing is wrong, so a clean file costs one exit and no context
# - extracts the touched file path from claude payloads
# @see plugins/retardify/skills/file/, .claude/settings.json

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

# the validator lives in the retardify plugin, which sits beside this one in the same checkout
SKILLS=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../retardify/skills" 2>/dev/null && pwd || true)
# a missing directory means a rename moved the validator, which would silently disable this hook
if [ ! -d "$SKILLS" ]; then
  echo "posttooluse: no retardify/skills beside this hook; file linting is off" >&2
  exit 0
fi

# it exits 1 on ERROR, which is right for a gate and wrong here: this hook never fails a write,
# so the exit code is absorbed and only what it printed is passed along
FINDINGS=$(
  bash "$SKILLS/file/file.sh" "$FILE" 2>/dev/null \
    | grep -E '^(ERROR|WARN)[[:space:]]' | head -n "$MAX_FINDINGS" || true
)

if [ -z "$FINDINGS" ]; then exit 0; fi

jq -n --arg ctx "file shape findings for $FILE (see /retardify:file);
fix the ERRORs, justify or fix the WARNs:
$FINDINGS" \
  '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $ctx}}'

exit 0

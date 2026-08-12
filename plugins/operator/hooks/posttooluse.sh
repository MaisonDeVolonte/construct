#!/bin/bash
# ==============================================
# @file posttooluse.sh - posttooluse hook script
# ==============================================
# @description
# - runs `eslint --fix`, then `/retardify:file` and `/retardify:code`, after a Write|Edit
# - file grades the shape around the logic; code grades the mechanics inside it
# - findings come back as context, agent fixes them on its next turn
# - silent when nothing is wrong, so a clean file costs two exits and no context
# - extracts the touched file path from claude payloads
# - anchors to the project root first, so a relative payload path resolves the same from any cwd
# @see plugins/retardify/skills/file/, .claude/settings.json

# hooks inherit the session's cwd, so anchor first; every path below stays relative to the root
cd "${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}" || exit 0

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

# both sidecars exit 1 on ERROR, which is right for a gate and wrong here: this hook never fails
# a write, so each exit code is absorbed and only what it printed is passed along
lint() {
  bash "$SKILLS/$1/$1.sh" "$FILE" 2>/dev/null | grep -E '^(ERROR|WARN)[[:space:]]' || true
}

SHAPE=$(lint file)
LOGIC=$(lint code)

# each sidecar gets half the budget, so a noisy shape report cannot crowd out every logic finding
SHARE=$((MAX_FINDINGS / 2))
FINDINGS=$({ printf '%s\n' "$SHAPE" | head -n "$SHARE"
             printf '%s\n' "$LOGIC" | head -n "$SHARE"; } | grep -E '^(ERROR|WARN)' || true)

if [ -z "$FINDINGS" ]; then exit 0; fi

# a cap that hides its own truncation reads as a clean bill of health, so the count says otherwise
FOUND=$(printf '%s\n%s\n' "$SHAPE" "$LOGIC" | grep -cE '^(ERROR|WARN)' || true)
SHOWN=$(printf '%s\n' "$FINDINGS" | grep -cE '^(ERROR|WARN)' || true)
if [ "$FOUND" -gt "$SHOWN" ]; then
  FINDINGS="$FINDINGS
$((FOUND - SHOWN)) more finding(s) hidden; run either sidecar on this path to see them all"
fi

jq -n --arg ctx "file and code findings for $FILE (see /retardify:file, /retardify:code);
fix the ERRORs, justify or fix the WARNs:
$FINDINGS" \
  '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $ctx}}'

exit 0

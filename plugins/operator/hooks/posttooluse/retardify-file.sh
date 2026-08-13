#!/bin/bash
# ==============================================================
# @file retardify-file.sh - file-shape findings after each write
# ==============================================================
# @description
# - fires after a Write or Edit lands: runs the `/retardify:file` sidecar on the touched file
# - file grades the shape around the logic; `/retardify:code` grades the mechanics inside it
# - findings come back as context, and the agent fixes them on its next turn
# - silent when nothing is wrong, so a clean file costs one exit and no context
# - carries its own findings cap; an independent cap replaces the sibling-halving the split ended
# - degrades to one stderr line when the retardify plugin is not installed beside operator
# - anchors to the project root first, so a relative payload path resolves the same from any cwd
# @see plugins/retardify/skills/file/, plugins/operator/hooks/hooks.json, plugins/operator/hooks/posttooluse/retardify-code.sh

command -v jq >/dev/null 2>&1 || exit 0

# hooks inherit the session's cwd, so anchor first; every path below stays relative to the root
cd "${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}" || exit 0

# the sidecar reports per finding, and a long file could bury the turn in shape notes
MAX_FINDINGS=10

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

# the validator lives in the retardify plugin, which sits beside this one in the same checkout
SKILLS=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../retardify/skills" 2>/dev/null && pwd || true)
if [ ! -d "$SKILLS" ]; then
  echo "retardify-file: no retardify/skills beside this hook; file linting is off" >&2
  exit 0
fi

# the sidecar exits 1 on ERROR, which is right for a gate and wrong here: this hook never fails
# a write, so the exit code is absorbed and only what it printed is passed along
REPORT=$(bash "$SKILLS/file/file.sh" "$FILE" 2>/dev/null | grep -E '^(ERROR|WARN)[[:space:]]' || true)
if [ -z "$REPORT" ]; then exit 0; fi

FINDINGS=$(printf '%s\n' "$REPORT" | head -n "$MAX_FINDINGS")

# a cap that hides its own truncation reads as a clean bill of health, so the count says otherwise
FOUND=$(printf '%s\n' "$REPORT" | grep -cE '^(ERROR|WARN)' || true)
SHOWN=$(printf '%s\n' "$FINDINGS" | grep -cE '^(ERROR|WARN)' || true)
if [ "$FOUND" -gt "$SHOWN" ]; then
  FINDINGS="$FINDINGS
$((FOUND - SHOWN)) more finding(s) hidden; run /retardify:file on this path to see them all"
fi

jq -n --arg ctx "file-shape findings for $FILE (see /retardify:file);
fix the ERRORs, justify or fix the WARNs:
$FINDINGS" \
  '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $ctx}}'

exit 0

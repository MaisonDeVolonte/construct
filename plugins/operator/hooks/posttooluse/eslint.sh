#!/bin/bash
# ====================================================
# @file eslint.sh - eslint --fix after javascript writes
# ====================================================
# @description
# - fires after a Write or Edit lands: runs `eslint --fix` on js, jsx, ts and tsx files
# - fixes land in place and silently; what eslint cannot fix is left to the retardify linters
# - silent for every other file type, and silent when the path no longer resolves
# - anchors to the project root first, so a relative payload path resolves the same from any cwd
# - self-contained on purpose: a manual install copies this one file and registers it
# @see plugins/operator/hooks/hooks.json, plugins/operator/hooks/posttooluse/retardify-file.sh

command -v jq >/dev/null 2>&1 || exit 0

# hooks inherit the session's cwd, so anchor first; every path below stays relative to the root
cd "${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}" || exit 0

FILE=$(jq -r '
  .tool_response.filePath
  // .tool_response.file_path
  // .tool_input.file_path
  // .toolInput.file_path
  // .toolInput.path
  // empty
')

# a rename or a delete leaves a path that no longer resolves, and there is nothing to fix
if [ -z "$FILE" ] || [ ! -f "$FILE" ]; then exit 0; fi

case "$FILE" in
  *.js|*.jsx|*.ts|*.tsx) npx eslint --fix "$FILE" 2>/dev/null ;;
esac

exit 0

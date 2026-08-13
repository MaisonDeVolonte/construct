#!/bin/bash
# ==============================================================
# @file block-outside-moves.sh - denies moves that leave the repo
# ==============================================================
# @description
# - fires before a Bash call runs: denies any `mv` whose destination lands outside the repo root
# - a move out of the repo is `rm` by another name; nothing is staged, so no git object holds it
# - an in-repo rename is ordinary work and passes silently, so renames never pay for the check
# - denies rather than asks; a blocked command is handed back for the user to run themselves
# - splits compounds on UNQUOTED `&|;` via `shared/commands.sh`, the one file this action needs
# - the destination is the last token of the segment, since `mv` takes no trailing option
# @see plugins/operator/shared/commands.sh, plugins/operator/hooks/hooks.json, plugins/operator/shared/corpus.tsv, plugins/operator/skills/permissions/permissions.sh

command -v jq >/dev/null 2>&1 || { echo "block-outside-moves: jq missing, refusing to run unguarded" >&2; exit 2; }

# the splitter is the one shared piece; a missing copy refuses to run unguarded, like the jq guard
COMMANDS="$(dirname "${BASH_SOURCE[0]}")/../../shared/commands.sh"
[ -f "$COMMANDS" ] || { echo "block-outside-moves: shared/commands.sh missing, refusing to run unguarded" >&2; exit 2; }
# shellcheck source=../../shared/commands.sh
. "$COMMANDS"

CMD=$(jq -r '.tool_input.command // .toolInput.command // empty')

# nothing to inspect
[ -z "$CMD" ] && exit 0

deny() {
  jq -n --arg reason "$1" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $reason
    }
  }'
  exit 0
}

# hooks inherit the session's cwd, so the repo root is resolved rather than assumed
REPO="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

while IFS= read -r segment; do
  if ! printf '%s' "$segment" | grep -qE '(^|[[:space:]])mv([[:space:]]|$)'; then continue; fi
  dest=$(printf '%s' "$segment" | awk '{print $NF}')
  dest=${dest%\"}; dest=${dest#\"}; dest=${dest%\'}; dest=${dest#\'}
  case "$dest" in
    '~'*|'$TMPDIR'*|'${TMPDIR}'*|..|../*)
      deny "blocked by block-outside-moves: this move lands outside the repo, where git cannot recover it. run it yourself if you really mean to." ;;
    /*)
      case "$dest" in
        "$REPO"|"$REPO"/*) ;;
        *) deny "blocked by block-outside-moves: this move lands outside the repo, where git cannot recover it. run it yourself if you really mean to." ;;
      esac ;;
  esac
done < <(split_unquoted "$CMD")

exit 0

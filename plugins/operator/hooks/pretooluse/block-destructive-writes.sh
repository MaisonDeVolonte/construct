#!/bin/bash
# ==============================================================
# @file block-destructive-writes.sh - denies writes with no undo
# ==============================================================
# @description
# - fires before a Bash call runs: denies write shapes that destroy, on ANY path
# - the sibling `block-protected-paths.sh` asks WHERE a write lands; this one asks WHAT it does
# - that split is why neither file grows a copy of the other's list
# - splits compounds on UNQUOTED `&|;` via `shared/commands.sh`, the one file this action needs
# - denies rather than asks; a blocked command is handed back for the user to run themselves
# - silent (exit 0) for everything else, so ordinary work never pays for the check
# - #1: an in-place editor rewrites the file it read, so the previous bytes exist nowhere
# - #2: a fetch-to-file writes whatever a remote sent, which no diff was shown before it landed
# - #3: a single `>` is judged only when the target already exists, so `>>` and new files pass
# - #4: `rm` stays out on purpose; a single-file delete is ordinary and the deny list holds `rm -r`
# @see plugins/operator/shared/commands.sh, plugins/operator/hooks/hooks.json, plugins/operator/shared/corpus.tsv, plugins/operator/skills/permissions/permissions.sh

command -v jq >/dev/null 2>&1 || { echo "block-destructive-writes: jq missing, refusing to run unguarded" >&2; exit 2; }

# the splitter is the one shared piece; a missing copy refuses to run unguarded, like the jq guard
COMMANDS="$(dirname "${BASH_SOURCE[0]}")/../../shared/commands.sh"
[ -f "$COMMANDS" ] || { echo "block-destructive-writes: shared/commands.sh missing, refusing to run unguarded" >&2; exit 2; }
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

# ── IN PLACE ─── the editor rewrites what it read, and `sed -n` never matches this (see #1)
INPLACE='(^|[[:space:]])(sed|perl|ruby)[[:space:]]+([^[:space:]]+[[:space:]]+)*'
INPLACE="$INPLACE"'-([a-zA-Z]*i|-in-place)'

# ── TRUNCATE ─── the file survives and its contents do not, which no git object holds
TRUNCATE='(^|[[:space:]])(truncate|shred|dd)([[:space:]]|$)'

# ── METADATA ─── a mode or owner flip is not undone by a checkout, since git tracks neither fully
METADATA='(^|[[:space:]])(chmod|chown)([[:space:]]|$)'

# ── CLOBBER ─── each of these overwrites a named destination without reading it first
CLOBBER='(^|[[:space:]])ln[[:space:]]+-[a-zA-Z]*f'
# anchored at command position, since npm, pnpm and make all take `install` as a subcommand
CLOBBER="$CLOBBER"'|(^|\|[[:space:]]*)install([[:space:]]|$)'
CLOBBER="$CLOBBER"'|(^|[[:space:]])tee([[:space:]]|$)'

# ── FETCH ─── the bytes come from a remote and land on disk unreviewed (see #2)
FETCH='(^|[[:space:]])curl[[:space:]].*[[:space:]]-(o|O|-output)([[:space:]]|$)'
FETCH="$FETCH"'|(^|[[:space:]])curl[[:space:]]+-[a-zA-Z]*[oO]([[:space:]]|$)'
FETCH="$FETCH"'|(^|[[:space:]])wget([[:space:]]|$)'

# `rm` is absent from every class above, and the deny list still holds its recursive forms (see #4)
DESTRUCTIVE="$INPLACE|$TRUNCATE|$METADATA|$CLOBBER|$FETCH"

while IFS= read -r segment; do
  if printf '%s' "$segment" | grep -qE "$DESTRUCTIVE"; then
    deny "blocked by block-destructive-writes: a write with no undo. run it yourself if you really mean to."
  fi
  # a single `>` is judged by its target, so only an existing file denies (see #3)
  while IFS= read -r target; do
    [ -n "$target" ] || continue
    [ -f "$target" ] || continue
    deny "blocked by block-destructive-writes: > truncates an existing file. use >> or run it yourself."
  done < <(printf '%s' "$segment" | grep -oE '(^|[^>0-9&])>[[:space:]]*[^>|[:space:]]+' \
    | sed -E 's/^[^>]*>[[:space:]]*//' || true)
done < <(split_unquoted "$CMD")

exit 0

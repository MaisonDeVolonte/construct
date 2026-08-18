#!/bin/bash
# ===================================================
# @file block-protected-paths.sh - denies bash writes
# ===================================================
# @description
# - fires before a Bash call runs: denies writers, heredocs and redirects aimed at policy paths
# - the Edit and Write deny rules are tool-scoped, so `cp`, `tee` and a redirect never meet them
# - splits compounds on UNQUOTED `&|;` via `shared/commands.sh`, the one file this action needs
# - denies rather than asks; a blocked command is handed back for the user to run themselves
# - silent (exit 0) for everything else, so ordinary work never pays for the check
# - #1: a directory is protected as itself, not only as a prefix; taking one whole kills its hooks
# - #2: any interpreter beside a policy path counts as a writer; cat, grep and bash stay free
# - #3: a heredoc splits interpreter from program by line, so it is judged as a whole command
# - #4: a runtime-resolved target beside a policy path denies; no static read can follow it
# - #5: a delivery tool sends a path to github without writing it here, so it denies too
# @see plugins/operator/shared/commands.sh, plugins/operator/hooks/hooks.json, plugins/operator/shared/corpus.tsv, plugins/operator/skills/permissions/permissions.sh

command -v jq >/dev/null 2>&1 || { echo "block-protected-paths: jq missing, refusing to run unguarded" >&2; exit 2; }

# the splitter is the one shared piece; a missing copy refuses to run unguarded, like the jq guard
COMMANDS="$(dirname "${BASH_SOURCE[0]}")/../../shared/commands.sh"
[ -f "$COMMANDS" ] || { echo "block-protected-paths: shared/commands.sh missing, refusing to run unguarded" >&2; exit 2; }
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

# the boundary keeps a bare prefix from matching a longer name, so `.git` never matches `.gitignore`
B='([/[:space:]"'"'"']|$)'

# ── DEFAULT ─── the compiled-in floor; the config below extends it and can never shrink it ─────
# each entry is a finished regex fragment, so one that must also match a suffix simply omits $B
DEFAULT_PROTECTED_PATHS=(
  # the harness's own policy, then every other agent's config directory
  "\.claude$B" "\.git$B" "\.husky$B" "\.devin$B" "\.cursor$B" "\.grok$B"

  # unbounded on purpose, so `.tfstate.backup` and `docker-compose.prod.yml` match too
  "\.tfstate" "docker-compose\.prod"

  # anchored at the front instead, since `.env` is matched as the tail of a filename
  "(^|[/[:space:]])\.env"

  # a command something else runs for you: the harness reads one, github reads the other
  "\.mcp\.json$B" "\.github/workflows$B"

  # the policy directories: hooks.json is the pointer, so the folder is the unit (see #1)
  "plugins/operator/settings$B" "plugins/[a-z][a-z-]*/hooks$B"

  # the probes read the live gate, so editing one lets an agent fake its own clean bill of health
  "plugins/operator/skills/(setup|credentials|permissions|scripts|settings)$B"

  # the config names more paths, so it is guarded here and never from itself: a file declaring its
  # own protection could be rewritten first and everything opened afterwards
  "construct\.config\.json$B"
)

# grep -E takes one pattern, so the entries become a single alternation. `local IFS` scopes the
# separator to this call, and "$*" is what joins on it; the loop form would need the same trick
join_alternation() {
  local IFS='|'
  printf '%s' "$*"
}
ALL_PROTECTED_PATHS=$(join_alternation "${DEFAULT_PROTECTED_PATHS[@]}")

# ── CONFIGURED ─── `policy.protected_paths`, which only ever adds to the floor above ─────────────
# missing, unreadable, unparseable or empty all leave PROTECTED exactly as compiled, so deleting
# the config protects nothing extra rather than protecting nothing at all
# entries are globs rather than regex: `**` spans directories, `*` stops at one segment
glob_to_regex() {
  printf '%s' "$1" \
    | sed -e 's/[][(){}.^$+|\\]/\\&/g' -e 's#\*\*#\x01#g' -e 's#\*#[^/]*#g' -e 's#\x01#.*#g'
}
CONFIG_FILE="${CLAUDE_PROJECT_DIR:-.}/construct.config.json"
if [ -r "$CONFIG_FILE" ] && command -v jq >/dev/null 2>&1; then
  while IFS= read -r glob; do
    [ -n "$glob" ] || continue
    ALL_PROTECTED_PATHS="$ALL_PROTECTED_PATHS|$(glob_to_regex "$glob")$B"
  done < <(jq -r '.policy.protected_paths[]? // empty' "$CONFIG_FILE" 2>/dev/null || true)
fi

# `.claude` is matched whole above, which swept in this repo's own maintainer skills; blanking the
# token beats an exception, since a command that ALSO names a policy path still earns its deny
unpolicy() {
  printf '%s' "$1" | sed -E 's#\.claude/skills(/[^[:space:]"'"'"']*)?#CLAUDE_SKILL#g'
}
WRITERS='(^|[[:space:]])(cp|mv|rm|tee|ln|install|rsync|truncate|shred|chmod|chown|dd|touch)([[:space:]]|$)'
INTERPRETER='(^|[[:space:]])(sed|perl|awk|python[0-9]?|ruby|node|deno|bun)([[:space:]]|$)'

# a delivery tool writes to github rather than to this disk, so no rule above ever sees it (see #5)
PUBLISHER='(^|[[:space:]]|/)(deliver\.sh[[:space:]]+(bucket|update)|gh)([[:space:]]|$)'

# a heredoc's interpreter and program never meet in one segment, so judge the whole command (see #3)
if printf '%s' "$CMD" | grep -q '<<' \
   && printf '%s' "$CMD" | grep -qE "$INTERPRETER" \
   && unpolicy "$CMD" | grep -qE "$ALL_PROTECTED_PATHS"; then
  deny "blocked by block-protected-paths: heredoc into a deny-listed path. run it yourself if you really mean to."
fi

# a compound command splits first, so `cat .git/config > /tmp/x` is not misread as writing to .git
while IFS= read -r segment; do
  if ! unpolicy "$segment" | grep -qE "$ALL_PROTECTED_PATHS"; then continue; fi
  # a protected path leaves this machine only when the user sends it themselves
  if printf '%s' "$segment" | grep -qE "$PUBLISHER"; then
    deny "blocked by block-protected-paths: a deny-listed path cannot be delivered for you. run this bucket yourself."
  fi
  # any interpreter beside a guarded path counts as a writer (see #2)
  if printf '%s' "$segment" | grep -qE "$WRITERS" || printf '%s' "$segment" | grep -qE "$INTERPRETER"; then
    deny "blocked by block-protected-paths: writes into a deny-listed path. run it yourself if you really mean to."
  fi
  # only a redirect TARGET counts, since reading a protected file out to somewhere else is fine
  while IFS= read -r target; do
    if [ -z "$target" ]; then continue; fi
    if unpolicy "$target" | grep -qE "$ALL_PROTECTED_PATHS"; then
      deny "blocked by block-protected-paths: redirects into a deny-listed path. run it yourself if you really mean to."
    fi
  done < <(printf '%s' "$segment" | grep -oE '>>?[[:space:]]*[^[:space:]]+' | sed -E 's/^>>?[[:space:]]*//' || true)
done < <(split_unquoted "$CMD")

# a runtime-resolved target beside a guarded path is the heredoc gap one indirection further out
# it runs AFTER the segment loop so a literal write earns the more specific reason above (see #4)
INPLACE='(sed|perl|ruby|python[0-9]?)([[:space:]]+-[^[:space:]]+)*[[:space:]]+-i([[:space:]]|$)'
VARTARGET='>>?[[:space:]]*"?\$\{?[A-Za-z_]'
VARTARGET="$VARTARGET"'|(^|[[:space:]])(cp|mv|tee|install|rsync|ln|truncate|dd)[[:space:]][^&|;]*\$\{?[A-Za-z_]'
if unpolicy "$CMD" | grep -qE "$ALL_PROTECTED_PATHS" \
   && printf '%s' "$CMD" | grep -qE "$INPLACE|$VARTARGET"; then
  deny "blocked by block-protected-paths: the write target resolves at runtime and a deny-listed path is named beside it. run it yourself if you really mean to."
fi

exit 0

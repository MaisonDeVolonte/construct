#!/bin/bash
# ==================================================================
# @file block-policy-edits.sh - denies bash writes into policy paths
# ==================================================================
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
# @see plugins/operator/shared/commands.sh, plugins/operator/hooks/hooks.json, plugins/operator/shared/corpus.tsv, plugins/operator/skills/permissions/permissions.sh

command -v jq >/dev/null 2>&1 || { echo "block-policy-edits: jq missing, refusing to run unguarded" >&2; exit 2; }

# the splitter is the one shared piece; a missing copy refuses to run unguarded, like the jq guard
COMMANDS="$(dirname "${BASH_SOURCE[0]}")/../../shared/commands.sh"
[ -f "$COMMANDS" ] || { echo "block-policy-edits: shared/commands.sh missing, refusing to run unguarded" >&2; exit 2; }
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
PROTECTED="\.claude$B|\.git$B|\.husky$B|\.devin$B|\.cursor$B|\.grok$B|webflow$B"
PROTECTED="$PROTECTED"'|\.tfstate|docker-compose\.prod'
PROTECTED="$PROTECTED"'|(^|[/[:space:]])\.env'
# an mcp server definition is a command the harness runs, so it is policy the same way a hook is
PROTECTED="$PROTECTED|\.mcp\.json$B"
# the policy directories: hooks.json is the pointer, so the folder is the unit (see #1)
PROTECTED="$PROTECTED|plugins/operator/settings$B|plugins/[a-z][a-z-]*/hooks$B"

# the probes read the live gate, so editing one lets an agent fake its own clean bill of health
PROTECTED="$PROTECTED|plugins/operator/skills/(audit|credentials|permissions|scripts|settings)$B"

# `.claude` is matched whole above, which swept in this repo's own maintainer skills; blanking the
# token beats an exception, since a command that ALSO names a policy path still earns its deny
unpolicy() {
  printf '%s' "$1" | sed -E 's#\.claude/skills(/[^[:space:]"'"'"']*)?#CLAUDE_SKILL#g'
}
WRITERS='(^|[[:space:]])(cp|mv|rm|tee|ln|install|rsync|truncate|shred|chmod|chown|dd|touch)([[:space:]]|$)'
INTERPRETER='(^|[[:space:]])(sed|perl|awk|python[0-9]?|ruby|node|deno|bun)([[:space:]]|$)'

# a heredoc's interpreter and program never meet in one segment, so judge the whole command (see #3)
if printf '%s' "$CMD" | grep -q '<<' \
   && printf '%s' "$CMD" | grep -qE "$INTERPRETER" \
   && unpolicy "$CMD" | grep -qE "$PROTECTED"; then
  deny "blocked by block-policy-edits: heredoc into a deny-listed path. run it yourself if you really mean to."
fi

# a compound command splits first, so `cat .git/config > /tmp/x` is not misread as writing to .git
while IFS= read -r segment; do
  if ! unpolicy "$segment" | grep -qE "$PROTECTED"; then continue; fi
  # any interpreter beside a policy path counts as a writer (see #2)
  if printf '%s' "$segment" | grep -qE "$WRITERS" || printf '%s' "$segment" | grep -qE "$INTERPRETER"; then
    deny "blocked by block-policy-edits: writes into a deny-listed path. run it yourself if you really mean to."
  fi
  # only a redirect TARGET counts, since reading a protected file out to somewhere else is fine
  while IFS= read -r target; do
    if [ -z "$target" ]; then continue; fi
    if unpolicy "$target" | grep -qE "$PROTECTED"; then
      deny "blocked by block-policy-edits: redirects into a deny-listed path. run it yourself if you really mean to."
    fi
  done < <(printf '%s' "$segment" | grep -oE '>>?[[:space:]]*[^[:space:]]+' | sed -E 's/^>>?[[:space:]]*//' || true)
done < <(split_unquoted "$CMD")

# a runtime-resolved target beside a policy path is the heredoc gap one indirection further out
# it runs AFTER the segment loop so a literal write earns the more specific reason above (see #4)
INPLACE='(sed|perl|ruby|python[0-9]?)([[:space:]]+-[^[:space:]]+)*[[:space:]]+-i([[:space:]]|$)'
VARTARGET='>>?[[:space:]]*"?\$\{?[A-Za-z_]'
VARTARGET="$VARTARGET"'|(^|[[:space:]])(cp|mv|tee|install|rsync|ln|truncate|dd)[[:space:]][^&|;]*\$\{?[A-Za-z_]'
if unpolicy "$CMD" | grep -qE "$PROTECTED" \
   && printf '%s' "$CMD" | grep -qE "$INPLACE|$VARTARGET"; then
  deny "blocked by block-policy-edits: the write target resolves at runtime and a deny-listed path is named beside it. run it yourself if you really mean to."
fi

exit 0

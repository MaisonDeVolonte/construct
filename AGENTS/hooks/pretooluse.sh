#!/bin/bash
# ==============================================
# @file pretooluse.sh - pretooluse hook script
# ==============================================
# @description
# - runs before a Bash tool call executes, can block it
# - FAILOVER for the deny list in `.claude/settings.json`, never the primary gate
# - deny rules are prefix anchored, so a trailing `--force` walks straight past them
# - this reads the FULL command string, so the flag gets caught wherever it sits
# - keep both: deny rules are committed, while this hook's wiring is gitignored
# - neither layer sees inside `AGENTS/git/*.sh`, since a script's commands are not tool calls
# - blocks force pushes and force branch deletes, silent (exit 0) for everything else
# @see AGENTS.md, .claude/settings.json, .claude/settings.local.json

command -v jq >/dev/null 2>&1 || { echo "pretooluse: jq missing, refusing to run unguarded" >&2; exit 2; }

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

# force push: `git push` present AND a -f / --force[...] flag token anywhere
if printf '%s' "$CMD" | grep -Eq '(^|[[:space:]])git[[:space:]]+push([[:space:]]|$)'; then
  if printf '%s' "$CMD" | grep -Eq '(^|[[:space:]])(-f|--force[^[:space:]]*)([[:space:]]|$)'; then
    deny "blocked by pretooluse hook: force push detected. run it yourself if you really mean to."
  fi
fi

# force branch delete: `git branch` present AND -D, or --delete together with --force
if printf '%s' "$CMD" | grep -Eq '(^|[[:space:]])git[[:space:]]+branch([[:space:]]|$)'; then
  if printf '%s' "$CMD" | grep -Eq '(^|[[:space:]])-D([[:space:]]|$)'; then
    deny "blocked by pretooluse hook: force branch delete (-D) detected. run it yourself if you really mean to."
  fi
  if printf '%s' "$CMD" | grep -Eq '(^|[[:space:]])--delete([[:space:]]|$)' \
     && printf '%s' "$CMD" | grep -Eq '(^|[[:space:]])(-f|--force)([[:space:]]|$)'; then
    deny "blocked by pretooluse hook: force branch delete (--delete --force) detected. run it yourself if you really mean to."
  fi
fi

# the Edit and Write deny rules are tool-scoped, so they say nothing about `cp`, `tee` or a
# redirect; the same paths get a second gate here, since bash reaches what those tools cannot
PROTECTED='\.claude/|\.git/|\.husky/|\.devin/|\.cursor/|webflow/|\.tfstate|docker-compose\.prod'
PROTECTED="$PROTECTED"'|(^|[/[:space:]])\.env'
WRITERS='(^|[[:space:]])(cp|mv|rm|tee|ln|install|rsync|truncate|shred|chmod|chown|dd|touch)([[:space:]]|$)'
INPLACE='(sed|perl|awk|python[0-9]?|ruby)[^|;&]*[[:space:]]-i'

# a compound command splits first, so `cat .git/config > /tmp/x` is not misread as writing to .git
while IFS= read -r segment; do
  if ! printf '%s' "$segment" | grep -qE "$PROTECTED"; then continue; fi
  if printf '%s' "$segment" | grep -qE "$WRITERS" || printf '%s' "$segment" | grep -qE "$INPLACE"; then
    deny "blocked by pretooluse hook: writes into a deny-listed path. run it yourself if you really mean to."
  fi
  # only a redirect TARGET counts, since reading a protected file out to somewhere else is fine
  while IFS= read -r target; do
    if [ -z "$target" ]; then continue; fi
    if printf '%s' "$target" | grep -qE "$PROTECTED"; then
      deny "blocked by pretooluse hook: redirects into a deny-listed path. run it yourself if you really mean to."
    fi
  done < <(printf '%s' "$segment" | grep -oE '>>?[[:space:]]*[^[:space:]]+' | sed -E 's/^>>?[[:space:]]*//' || true)
done < <(printf '%s\n' "$CMD" | tr '&|;' '\n')

exit 0

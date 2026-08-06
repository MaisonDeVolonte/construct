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
# - neither layer sees inside `AGENTS/skills/*/*.sh`, since a script's commands are not tool calls
# - blocks force pushes and force branch deletes, silent (exit 0) for everything else
# - also guards the narrow allows `/git-continue` opens: ff-only merge, plain switch, stash halves
# - also refuses bash writes into the policy dirs, which the Edit and Write rules never see
# - asks, never denies, when a move lands outside the repo, since a rename is ordinary work
# @see AGENTS.md, .claude/settings.json, .claude/settings.local.json, AGENTS/settings/

command -v jq >/dev/null 2>&1 || { echo "pretooluse: jq missing, refusing to run unguarded" >&2; exit 2; }

CMD=$(jq -r '.tool_input.command // .toolInput.command // empty')

# nothing to inspect
[ -z "$CMD" ] && exit 0

decide() {
  jq -n --arg d "$1" --arg reason "$2" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: $d,
      permissionDecisionReason: $reason
    }
  }'
  exit 0
}

deny() { decide deny "$1"; }
# ask returns the prompt the mode may have removed, so the user judges the call rather than the rule
ask()  { decide ask  "$1"; }

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

# merge: a fast-forward moves a pointer and can never lose work, so only that shape gets through
if printf '%s' "$CMD" | grep -Eq '(^|[[:space:]])git[[:space:]]+merge([[:space:]]|$)'; then
  if ! printf '%s' "$CMD" | grep -Eq '(^|[[:space:]])--ff-only([[:space:]]|$)'; then
    deny "blocked by pretooluse hook: git merge without --ff-only. run it yourself if you really mean to."
  fi
fi

# switch: changing branch is fine, but creating, detaching or discarding the tree stays the user's
if printf '%s' "$CMD" | grep -Eq '(^|[[:space:]])git[[:space:]]+switch([[:space:]]|$)'; then
  if printf '%s' "$CMD" | grep -Eq '(^|[[:space:]])(-c|-C|-f|-d|--create|--force-create|--force|--discard-changes|--orphan|--detach)([[:space:]]|$)'; then
    deny "blocked by pretooluse hook: git switch with a create, detach or discard flag. run it yourself if you really mean to."
  fi
fi

# the Edit and Write deny rules are tool-scoped, so they say nothing about `cp`, `tee` or a
# redirect; the same paths get a second gate here, since bash reaches what those tools cannot
PROTECTED='\.claude/|\.git/|\.husky/|\.devin/|\.cursor/|webflow/|\.tfstate|docker-compose\.prod'
PROTECTED="$PROTECTED"'|(^|[/[:space:]])\.env'
# the policy directories: settings rules gate the Edit and Write tools, and this gates the bash
# verbs those rules never see, since an agent that can rewrite either one can regrant itself
PROTECTED="$PROTECTED"'|AGENTS/settings/|AGENTS/hooks/'
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

# a move out of the repo is `rm` by another name: nothing is staged, so no git object holds it
# an in-repo rename is ordinary work, so this asks for the destination rather than denying it
REPO=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
while IFS= read -r segment; do
  if ! printf '%s' "$segment" | grep -qE '(^|[[:space:]])mv([[:space:]]|$)'; then continue; fi
  # the destination is the last token, since `mv` takes no trailing option
  dest=$(printf '%s' "$segment" | awk '{print $NF}')
  dest=${dest%\"}; dest=${dest#\"}; dest=${dest%\'}; dest=${dest#\'}
  case "$dest" in
    '~'*|'$TMPDIR'*|'${TMPDIR}'*|..|../*)
      ask "pretooluse hook: this move lands outside the repo, where git cannot recover it. confirm the destination." ;;
    /*)
      case "$dest" in
        "$REPO"|"$REPO"/*) ;;
        *) ask "pretooluse hook: this move lands outside the repo, where git cannot recover it. confirm the destination." ;;
      esac ;;
  esac
done < <(printf '%s\n' "$CMD" | tr '&|;' '\n')

exit 0

#!/bin/bash
# ========================================
# @file pretooluse.sh - deny list failover
# ========================================
# @description
# - failover for the deny list in `.claude/settings.json`
# - runs before a Bash tool call executes, reads full command string, can block it
# - designed to catch trailing `--evil` flags (deny rules are prefix anchored)
# - neither deny list nor pretooluse catch commands inside `.sh` scripts (only work on tool calls)
# - blocks force pushes, branch deletes, etc; silent (exit 0) for everything else
# - blocks bash writes into policy directories (Edit/Write rules don't see bash)
# - asks when moving files outside the repo root (renames are ordinary work)
# @see .claude/settings.json, .claude/settings.local.json, plugins/operator/settings/

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
# a directory is protected as itself, not only as a prefix of its contents: every pattern used to
# end in `/`, so removing `plugins/operator/hooks` was allowed where removing a file inside it was
# denied, and taking the directory neutralises all six hooks at once (see #33). the boundary keeps
# a bare prefix from matching a longer name, so `.git` never matches `.gitignore`
B='([/[:space:]"'"'"']|$)'
PROTECTED="\.claude$B|\.git$B|\.husky$B|\.devin$B|\.cursor$B|webflow$B"
PROTECTED="$PROTECTED"'|\.tfstate|docker-compose\.prod'
PROTECTED="$PROTECTED"'|(^|[/[:space:]])\.env'
# the policy directories: settings rules gate the Edit and Write tools, and this gates the bash
# verbs those rules never see, since an agent that can rewrite either one can regrant itself
PROTECTED="$PROTECTED|plugins/operator/settings$B|plugins/operator/hooks$B"
# the probes read the live gate, so editing one lets an agent fake its own clean bill of health
PROTECTED="$PROTECTED|plugins/operator/skills/(credentials|permissions|scopes|settings)$B"
WRITERS='(^|[[:space:]])(cp|mv|rm|tee|ln|install|rsync|truncate|shred|chmod|chown|dd|touch)([[:space:]]|$)'
# an interpreter writes as its ordinary work, so `-i` was never the shape to catch: a heredoc
# reaches every policy path the hook guards and `WRITERS` never fires, since no cp, mv or tee
# appears in the command string (see #47). the segment already named a policy path to get here,
# so any interpreter in it is treated as a writer. that over-blocks a read through python and
# leaves cat and grep untouched, and `bash` stays off the list so running a sidecar still works
INTERPRETER='(^|[[:space:]])(sed|perl|awk|python[0-9]?|ruby|node|deno|bun)([[:space:]]|$)'

# a heredoc puts the interpreter on one line and its program on the next, and the split below is by
# line, so the two never meet in one segment and the per-segment test cannot see them together
# that is the exact shape #47 called the worst case, so it is judged against the WHOLE command
if printf '%s' "$CMD" | grep -q '<<' \
   && printf '%s' "$CMD" | grep -qE "$INTERPRETER" \
   && printf '%s' "$CMD" | grep -qE "$PROTECTED"; then
  deny "blocked by pretooluse hook: heredoc into a deny-listed path. run it yourself if you really mean to."
fi

# a compound command splits first, so `cat .git/config > /tmp/x` is not misread as writing to .git
while IFS= read -r segment; do
  if ! printf '%s' "$segment" | grep -qE "$PROTECTED"; then continue; fi
  if printf '%s' "$segment" | grep -qE "$WRITERS" || printf '%s' "$segment" | grep -qE "$INTERPRETER"; then
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

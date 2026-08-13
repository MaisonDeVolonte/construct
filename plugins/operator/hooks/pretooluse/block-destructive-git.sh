#!/bin/bash
# ===================================================================
# @file block-destructive-git.sh - denies four destructive git shapes
# ===================================================================
# @description
# - fires before a Bash call runs: reads the command string, denies four destructive git shapes
# - force push, force branch delete, non-fast-forward merge, and an unsafe switch
# - denies rather than asks; a blocked command is handed back for the user to run themselves
# - flag tests span the whole string, so a trailing `--force` cannot hide behind its position
# - deny rules are prefix-anchored and miss trailing flags, which is the gap this action closes
# - silent (exit 0) for everything else, so ordinary work never pays for the check
# - self-contained on purpose: a manual install copies this one file and registers it
# @see plugins/operator/hooks/hooks.json, plugins/operator/shared/corpus.tsv, plugins/operator/skills/permissions/permissions.sh

command -v jq >/dev/null 2>&1 || { echo "block-destructive-git: jq missing, refusing to run unguarded" >&2; exit 2; }

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
    deny "blocked by block-destructive-git: force push detected. run it yourself if you really mean to."
  fi
fi

# force branch delete: `git branch` present AND -D, or --delete together with --force
if printf '%s' "$CMD" | grep -Eq '(^|[[:space:]])git[[:space:]]+branch([[:space:]]|$)'; then
  if printf '%s' "$CMD" | grep -Eq '(^|[[:space:]])-D([[:space:]]|$)'; then
    deny "blocked by block-destructive-git: force branch delete (-D) detected. run it yourself if you really mean to."
  fi
  if printf '%s' "$CMD" | grep -Eq '(^|[[:space:]])--delete([[:space:]]|$)' \
     && printf '%s' "$CMD" | grep -Eq '(^|[[:space:]])(-f|--force)([[:space:]]|$)'; then
    deny "blocked by block-destructive-git: force branch delete (--delete --force) detected. run it yourself if you really mean to."
  fi
fi

# merge: a fast-forward moves a pointer and can never lose work, so only that shape gets through
if printf '%s' "$CMD" | grep -Eq '(^|[[:space:]])git[[:space:]]+merge([[:space:]]|$)'; then
  if ! printf '%s' "$CMD" | grep -Eq '(^|[[:space:]])--ff-only([[:space:]]|$)'; then
    deny "blocked by block-destructive-git: git merge without --ff-only. run it yourself if you really mean to."
  fi
fi

# switch: changing branch is fine, but creating, detaching or discarding the tree stays the user's
if printf '%s' "$CMD" | grep -Eq '(^|[[:space:]])git[[:space:]]+switch([[:space:]]|$)'; then
  if printf '%s' "$CMD" | grep -Eq '(^|[[:space:]])(-c|-C|-f|-d|--create|--force-create|--force|--discard-changes|--orphan|--detach)([[:space:]]|$)'; then
    deny "blocked by block-destructive-git: git switch with a create, detach or discard flag. run it yourself if you really mean to."
  fi
fi

exit 0

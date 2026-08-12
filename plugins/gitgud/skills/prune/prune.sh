#!/bin/bash
# ===========================================
# @file prune.sh - post-merge cleanup sidecar
# ===========================================
# @description
# PAIR
# - sidecar for `/gitgud:prune` — finds spent branches, then hands the cleanup commands over
# - typically run post-merge, but safe anytime, since nothing in the pair deletes a branch
# SIDECAR
# - read-only apart from `fetch --prune`, which deletes no local branch and writes no tracked file
# - the trunk sync is handed over, never run: a sandboxed merge half-applies on a denied path
# - classifies each local branch as gone, merged, or live, so the handover deletes only the spent
# - emits `-d` or `-D` to match, since `-d` consults the same patch-id read a rebase already fooled
# - a gone branch that is neither merged nor absorbed is kept, never offered for deletion
# TRIGGER
# - the doc folds in `git-audit.sh`, whose local/remote/ghost/zombie split catches the rebased ones
# - stash and branch deletes are denied, so the whole block stays the user's to run in order
# @see plugins/gitgud/skills/prune/SKILL.md, plugins/gitgud/shared/triage.sh, plugins/gitgud/shared/handover.sh, .claude/skills/validate-skills/SKILL.md

set -euo pipefail

# the doc is read only after this has already run, so help is refused here or not at all; the doc's
# own '## Help' section owns the output, which is why this prints a marker rather than a usage text
case " $* " in *" --help "*|*" -h "*) echo "help: requested"; exit 0;; esac

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)
SHARED=$(cd "$HERE/../../shared" 2>/dev/null && pwd || true)
if [ ! -f "$SHARED/handover.sh" ]; then
  echo "fatal: no plugins/gitgud/shared/handover.sh reachable from this sidecar" >&2; exit 1; fi
# shellcheck source=../../shared/handover.sh
. "$SHARED/handover.sh"

require_repo
require_no_op_in_progress

DEFAULT_BRANCH=$(git_default_branch)
STARTING_BRANCH=$(git_current_branch)

if [ -z "$DEFAULT_BRANCH" ]; then
  echo "fatal: missing remote default branch" >&2; exit 1; fi
if [ -z "$STARTING_BRANCH" ]; then
  echo "fatal: detached HEAD" >&2; exit 1; fi

# --prune drops tracking refs for branches deleted on the remote, which is what marks their local
# counterparts 'gone' below; it deletes no local branch, so it stays inside the read-only contract
PRUNE_ERR=""
if ! PRUNE_ERR=$(git fetch --prune origin --quiet 2>&1); then
  echo "fatal: could not fetch origin" >&2
  echo "$PRUNE_ERR" >&2
  exit 1
fi

BEHIND=$(git rev-list --count "$DEFAULT_BRANCH..origin/$DEFAULT_BRANCH" 2>/dev/null || echo 0)
AHEAD=$(git rev-list --count "origin/$DEFAULT_BRANCH..$DEFAULT_BRANCH" 2>/dev/null || echo 0)

# --ff-only cannot lose work, but it can half apply it: a path the sandbox denies fails the merge
# after the writable ones landed, so the sync is measured here and run by the user (see #127)
PROTECTED_PATHS=""
if [ "$BEHIND" -gt 0 ]; then
  PROTECTED_PATHS=$(protected_incoming "$DEFAULT_BRANCH..origin/$DEFAULT_BRANCH" \
    | paste -sd, - | sed 's/,/, /g')
fi

# a branch is spent when its remote is gone, or when trunk already contains every commit on it;
# anything else is live work and never reaches the handover
GONE_BRANCHES=$(git for-each-ref --format='%(refname:short) %(upstream:track)' refs/heads/ \
  | awk '$2 == "[gone]" { print $1 }' | grep -vx "$DEFAULT_BRANCH" || true)
MERGED_BRANCHES=$(git branch --merged "origin/$DEFAULT_BRANCH" --format='%(refname:short)' \
  | grep -vx "$DEFAULT_BRANCH" || true)

SPENT_BRANCHES=$(printf '%s\n%s\n' "$GONE_BRANCHES" "$MERGED_BRANCHES" | grep -v '^$' | sort -u || true)
SPENT_COUNT=$(printf '%s' "$SPENT_BRANCHES" | grep -c . || true)

# -d succeeds only when the trunk contains the tip, which a rebase merge never leaves true
# those earn -D by proving absorption; a gone branch that is neither is kept, never offered
DELETE_SAFE=""
DELETE_FORCE=""
KEEP_BRANCHES=""
for branch in $SPENT_BRANCHES; do
  if printf '%s\n' "$MERGED_BRANCHES" | grep -qx "$branch"; then
    DELETE_SAFE="$DELETE_SAFE $branch"
  elif [ "$(is_absorbed "origin/$DEFAULT_BRANCH" "$branch")" = "yes" ]; then
    DELETE_FORCE="$DELETE_FORCE $branch"
  else
    KEEP_BRANCHES="$KEEP_BRANCHES $branch"
  fi
done
DELETE_COUNT=$(printf '%s' "$DELETE_SAFE $DELETE_FORCE" | tr ' ' '\n' | grep -c . || true)
LIVE_COUNT=$(git for-each-ref --format='%(refname:short)' refs/heads/ \
  | grep -vx "$DEFAULT_BRANCH" | grep -c . || true)
LIVE_COUNT=$((LIVE_COUNT - SPENT_COUNT))

telemetry_open gitgud:prune
telemetry_line "default branch" "$DEFAULT_BRANCH"
telemetry_line "current branch" "$STARTING_BRANCH"
telemetry_line "trunk behind origin" "$BEHIND"
telemetry_line "trunk ahead of origin" "$AHEAD"
telemetry_line "trunk sync" "$([ "$BEHIND" -gt 0 ] && echo "handed over" || echo "not needed")"
telemetry_line "sandbox-denied incoming paths" "${PROTECTED_PATHS:-none}"
telemetry_line "spent branches" "${SPENT_COUNT:-0}"
telemetry_line "live branches" "${LIVE_COUNT:-0}"
telemetry_line "spent branch names" "$(printf '%s' "$SPENT_BRANCHES" | paste -sd, - | sed 's/,/, /g')"
telemetry_line "deletable with -d" "$(printf '%s' "${DELETE_SAFE# }" | sed 's/ /, /g')"
telemetry_line "deletable with -D (absorbed)" "$(printf '%s' "${DELETE_FORCE# }" | sed 's/ /, /g')"
telemetry_line "kept, unmerged and unabsorbed" "$(printf '%s' "${KEEP_BRANCHES# }" | sed 's/ /, /g')"

handover_open gitgud:prune
if [ "$AHEAD" -gt 0 ]; then
  handover_note "$DEFAULT_BRANCH has $AHEAD commit(s) origin does not — resolve before cleaning up"
elif [ "$BEHIND" -eq 0 ] && [ "${DELETE_COUNT:-0}" -eq 0 ]; then
  handover_note "nothing to clean up — trunk is current and no branch is safe to delete"
  if [ -n "$KEEP_BRANCHES" ]; then
    handover_note "kept as real work:${KEEP_BRANCHES} — neither merged nor absorbed by $DEFAULT_BRANCH"
  fi
else
  handover_note "run these in order; the branch deletes are denied, so the block stays yours"
  if git_is_dirty; then
    handover_note "your tree is dirty — stash first if the switch below refuses"
  fi
  if [ "$BEHIND" -gt 0 ]; then
    if [ "$STARTING_BRANCH" != "$DEFAULT_BRANCH" ]; then
      handover_cmd "git switch $DEFAULT_BRANCH"
    fi
    handover_cmd "git merge --ff-only origin/$DEFAULT_BRANCH"
    if [ -n "$PROTECTED_PATHS" ]; then
      handover_note "the sync writes paths no sandboxed command can: $PROTECTED_PATHS"
      handover_note "run it in your own terminal, then confirm with: git diff origin/$DEFAULT_BRANCH"
    fi
  fi
  # -d refuses a branch trunk does not already contain, which is the safety this list relies on
  for branch in $DELETE_SAFE; do
    handover_cmd "git branch -d $branch"
  done
  # -D skips that check, so it is spent only where the tree comparison above already proved it safe
  for branch in $DELETE_FORCE; do
    handover_cmd "git branch -D $branch"
  done
  if [ -n "$KEEP_BRANCHES" ]; then
    handover_note "kept as real work:${KEEP_BRANCHES} — neither merged nor absorbed, so not offered"
  fi
  if [ "$BEHIND" -gt 0 ] && [ "$STARTING_BRANCH" != "$DEFAULT_BRANCH" ]; then
    handover_cmd "git switch $STARTING_BRANCH"
  fi
fi
block_close

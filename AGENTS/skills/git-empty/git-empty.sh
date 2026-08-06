#!/bin/bash
# ==============================================
# @file git-empty.sh - post-merge cleanup sidecar
# ==============================================
# @description
# - sidecar for `@git-empty` — finds spent branches, then hands the cleanup commands over
# - read-only apart from `fetch --prune` and a trunk fast-forward, neither of which loses work
# - classifies each local branch as gone, merged, or live, so the handover deletes only the spent
# - stash and branch deletes are denied, so it prints them instead of running them
# @see AGENTS.md, AGENTS/templates/git.md, AGENTS/skills/git-empty/SKILL.md, AGENTS/shared/handover.sh

set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)
SHARED=$(cd "$HERE/../../shared" 2>/dev/null && pwd || true)
if [ ! -f "$SHARED/handover.sh" ]; then
  echo "fatal: no AGENTS/shared/handover.sh reachable from this sidecar" >&2; exit 1; fi
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

# --ff-only cannot lose work: it refuses anything but a strict fast-forward, and refuses again
# over local changes; only from the trunk, since switching a branch out from under the user mutates
FAST_FORWARDED="no"
if [ "$BEHIND" -gt 0 ] && [ "$STARTING_BRANCH" = "$DEFAULT_BRANCH" ] && ! git_is_dirty; then
  if git merge --ff-only "origin/$DEFAULT_BRANCH" >/dev/null 2>&1; then
    FAST_FORWARDED="yes ($BEHIND commit(s))"
    BEHIND=0
  fi
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

telemetry_open git-empty
telemetry_line "default branch" "$DEFAULT_BRANCH"
telemetry_line "current branch" "$STARTING_BRANCH"
telemetry_line "trunk behind origin" "$BEHIND"
telemetry_line "trunk ahead of origin" "$AHEAD"
telemetry_line "trunk fast-forwarded" "$FAST_FORWARDED"
telemetry_line "spent branches" "${SPENT_COUNT:-0}"
telemetry_line "live branches" "${LIVE_COUNT:-0}"
telemetry_line "spent branch names" "$(printf '%s' "$SPENT_BRANCHES" | paste -sd, - | sed 's/,/, /g')"
telemetry_line "deletable with -d" "$(printf '%s' "${DELETE_SAFE# }" | sed 's/ /, /g')"
telemetry_line "deletable with -D (absorbed)" "$(printf '%s' "${DELETE_FORCE# }" | sed 's/ /, /g')"
telemetry_line "kept, unmerged and unabsorbed" "$(printf '%s' "${KEEP_BRANCHES# }" | sed 's/ /, /g')"

handover_open git-empty
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

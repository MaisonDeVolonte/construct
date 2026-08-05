#!/bin/bash
# ==============================================
# @file gitempty.sh - post-merge cleanup sidecar
# ==============================================
# @description
# - sidecar for `@gitempty` — finds spent branches, then hands the cleanup commands over
# - read-only apart from `fetch --prune`, which drops tracking refs and never a branch
# - classifies each local branch as gone, merged, or live, so the handover deletes only the spent
# - stash, switch, merge and branch deletes are all denied, so it prints them instead
# @see AGENTS.md, AGENTS/templates/git.md, AGENTS/git/gitempty.md, AGENTS/git/handover.sh

set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)
if [ ! -f "$HERE/handover.sh" ]; then
  echo "fatal: no AGENTS/git/handover.sh beside this sidecar" >&2; exit 1; fi
# shellcheck source=./handover.sh
. "$HERE/handover.sh"

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

# a branch is spent when its remote is gone, or when trunk already contains every commit on it;
# anything else is live work and never reaches the handover
GONE_BRANCHES=$(git for-each-ref --format='%(refname:short) %(upstream:track)' refs/heads/ \
  | awk '$2 == "[gone]" { print $1 }' | grep -vx "$DEFAULT_BRANCH" || true)
MERGED_BRANCHES=$(git branch --merged "origin/$DEFAULT_BRANCH" --format='%(refname:short)' \
  | grep -vx "$DEFAULT_BRANCH" || true)

SPENT_BRANCHES=$(printf '%s\n%s\n' "$GONE_BRANCHES" "$MERGED_BRANCHES" | grep -v '^$' | sort -u || true)
SPENT_COUNT=$(printf '%s' "$SPENT_BRANCHES" | grep -c . || true)
LIVE_COUNT=$(git for-each-ref --format='%(refname:short)' refs/heads/ \
  | grep -vx "$DEFAULT_BRANCH" | grep -c . || true)
LIVE_COUNT=$((LIVE_COUNT - SPENT_COUNT))

telemetry_open gitempty
telemetry_line "default branch" "$DEFAULT_BRANCH"
telemetry_line "current branch" "$STARTING_BRANCH"
telemetry_line "trunk behind origin" "$BEHIND"
telemetry_line "trunk ahead of origin" "$AHEAD"
telemetry_line "spent branches" "${SPENT_COUNT:-0}"
telemetry_line "live branches" "${LIVE_COUNT:-0}"
telemetry_line "spent branch names" "$(printf '%s' "$SPENT_BRANCHES" | paste -sd, - | sed 's/,/, /g')"

handover_open gitempty
if [ "$AHEAD" -gt 0 ]; then
  handover_note "$DEFAULT_BRANCH has $AHEAD commit(s) origin does not — resolve before cleaning up"
elif [ "$BEHIND" -eq 0 ] && [ "${SPENT_COUNT:-0}" -eq 0 ]; then
  handover_note "nothing to clean up — trunk is current and no branch is spent"
else
  handover_note "run these in order; each is denied as a tool call, so they are yours"
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
  for branch in $SPENT_BRANCHES; do
    handover_cmd "git branch -d $branch"
  done
  if [ "$BEHIND" -gt 0 ] && [ "$STARTING_BRANCH" != "$DEFAULT_BRANCH" ]; then
    handover_cmd "git switch $STARTING_BRANCH"
  fi
fi
block_close

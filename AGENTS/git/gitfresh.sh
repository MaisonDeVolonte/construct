#!/bin/bash
# ==================================================
# @file gitfresh.sh - hard-reset backup and handover
# ==================================================
# @description
# - sidecar for `@gitfresh` — backs local state up, then hands the destructive commands over
# - gated: never cleans, resets, or force-deletes; it prints those for the user to run by hand
# - the deny floor refuses all three as tool calls, so a sidecar running them was a silent bypass
# - the stash, the aborts, and the fetch stay, since each preserves state rather than drops it
# @see AGENTS.md, AGENTS/templates/git.md, AGENTS/git/gitfresh.md, AGENTS/git/gitempty.sh

# only run if the --confirmed flag is present
if [ "${1:-}" != "--confirmed" ]; then echo "refusing without --confirmed"; exit 1; fi
# exit if any command fails, including unset variables and pipeline errors
set -euo pipefail
# use remote default branch as local default branch
git remote set-head origin --auto >/dev/null || true

# initialize variables
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
STASH_NAME="gitfresh-$TIMESTAMP"
DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD | sed 's@^refs/remotes/origin/@@')
STARTING_BRANCH=$(git branch --show-current)
UNTRACKED_COUNT=$(git status --porcelain=v1 | grep -cE '^\?\?' || true)
MODIFIED_COUNT=$(git status --porcelain=v1 | grep -cE '^[ MADRCU]' || true)
SWITCH_STATUS="switched"
PENDING_BRANCH_COUNT=0
PENDING_BRANCH_NAMES=""
ALL_LOCAL_BRANCHES=$(git for-each-ref --format='%(refname:short)' refs/heads/ | grep -vx "$DEFAULT_BRANCH" || true)

# stash tracked and untracked as a backup
if [ -n "$(git status --porcelain)" ]; then
git stash push -a -m "$STASH_NAME" >/dev/null 2>&1
else STASH_NAME="none"; fi

# abort any broken in-progress operations
git merge --abort >/dev/null 2>&1 || true
git rebase --abort >/dev/null 2>&1 || true
git cherry-pick --abort >/dev/null 2>&1 || true

# get onto default and fetch pristine state; a forced switch discards, so it is handed over instead
if ! git switch "$DEFAULT_BRANCH" >/dev/null 2>&1; then SWITCH_STATUS="failed"; fi
git fetch --prune --all >/dev/null 2>&1

# measure what the handover would cost, after the fetch so origin is current
DISCARDED_COMMITS=$(git rev-list --count "origin/$DEFAULT_BRANCH..$DEFAULT_BRANCH" 2>/dev/null || echo 0)
GAINED_COMMITS=$(git rev-list --count "$DEFAULT_BRANCH..origin/$DEFAULT_BRANCH" 2>/dev/null || echo 0)

# name every branch the handover would delete
for branch in $ALL_LOCAL_BRANCHES; do
  PENDING_BRANCH_COUNT=$((PENDING_BRANCH_COUNT + 1))
  PENDING_BRANCH_NAMES="${PENDING_BRANCH_NAMES:+$PENDING_BRANCH_NAMES, }$branch"
done

# telemetry
echo "--- @gitfresh telemetry ---"
echo "shell command status: succeeded"
echo "initiated script on: $STARTING_BRANCH"
echo "default branch: $DEFAULT_BRANCH"
echo "switched to default: $SWITCH_STATUS"
echo "backup stash name: $STASH_NAME"
echo "untracked files backed up: $UNTRACKED_COUNT"
echo "modifications backed up: $MODIFIED_COUNT"
echo "commits the reset discards: $DISCARDED_COMMITS"
echo "commits the reset gains: $GAINED_COMMITS"
echo "branches pending deletion: $PENDING_BRANCH_COUNT"
echo "pending branch names: ${PENDING_BRANCH_NAMES:-none}"
echo "---------------------------"

# handover: each line below is refused as a tool call, so it is the user's to run, never the agent's
echo "--- @gitfresh handover ---"
echo "run these yourself, in this order:"
if [ "$SWITCH_STATUS" = "failed" ]; then echo "git switch -f $DEFAULT_BRANCH"; fi
echo "git clean -fd"
echo "git reset --hard origin/$DEFAULT_BRANCH"
for branch in $ALL_LOCAL_BRANCHES; do
  echo "git branch -D $branch"
done
echo "--------------------------"

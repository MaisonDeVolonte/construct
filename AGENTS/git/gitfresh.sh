#!/bin/bash
# ==================================================
# @file gitfresh.sh - destructive hard-reset sidecar
# ==================================================
# @description
# - sidecar for `@gitfresh` — nukes local state and syncs a pristine trunk to origin
# @see AGENTS.md, AGENTS/templates/git.md, AGENTS/git/gitfresh.md

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
DELETED_BRANCHES_COUNT=0
DELETED_BRANCHES_NAMES=""
ALL_LOCAL_BRANCHES=$(git for-each-ref --format='%(refname:short)' refs/heads/ | grep -vx "$DEFAULT_BRANCH" || true)

# stash tracked and untracked as a backup
if [ -n "$(git status --porcelain)" ]; then
git stash push -a -m "$STASH_NAME" >/dev/null 2>&1
else STASH_NAME="none"; fi

# abort any broken in-progress operations
git merge --abort >/dev/null 2>&1 || true
git rebase --abort >/dev/null 2>&1 || true
git cherry-pick --abort >/dev/null 2>&1 || true

# get onto default, fetch pristine state, wipe, and hard-reset
git switch "$DEFAULT_BRANCH" >/dev/null 2>&1 || git switch -f "$DEFAULT_BRANCH" >/dev/null 2>&1
git fetch --prune --all >/dev/null 2>&1
git clean -fd >/dev/null 2>&1
git reset --hard "origin/$DEFAULT_BRANCH" >/dev/null 2>&1

# delete every other local branch
for branch in $ALL_LOCAL_BRANCHES; do
  git branch -D "$branch" >/dev/null 2>&1
  DELETED_BRANCHES_COUNT=$((DELETED_BRANCHES_COUNT + 1))
  DELETED_BRANCHES_NAMES="${DELETED_BRANCHES_NAMES:+$DELETED_BRANCHES_NAMES, }$branch"
done

# verify the reset actually landed
if [ "$(git rev-parse HEAD)" = "$(git rev-parse "origin/$DEFAULT_BRANCH")" ]; then
  DEFAULT_BRANCH_STATUS="synced to origin"
else DEFAULT_BRANCH_STATUS="out of sync"; fi

# telemetry
echo "--- @gitfresh telemetry ---"
echo "shell command status: succeeded"
echo "initiated script on: $STARTING_BRANCH"
echo "default branch: $DEFAULT_BRANCH"
echo "backup stash name: $STASH_NAME"
echo "untracked files backed up: $UNTRACKED_COUNT"
echo "modifications backed up: $MODIFIED_COUNT"
echo "total branches deleted: $DELETED_BRANCHES_COUNT"
echo "deleted branch names: ${DELETED_BRANCHES_NAMES:-none}"
echo "default branch status: $DEFAULT_BRANCH_STATUS"
echo "---------------------------"

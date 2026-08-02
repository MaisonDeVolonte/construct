#!/bin/bash
# ==============================================
# @file gitempty.sh - post-merge cleanup sidecar
# ==============================================
# @description
# - sidecar for `@gitempty` — stash, prune dead remotes, fast-forward trunk
# - deliberately deletes NOTHING; `git fetch --prune` only drops tracking refs, never a branch
# - branch deletion is the trigger's job, and it hands the commands to the user to run
# @see AGENTS.md, AGENTS/templates/git.md, AGENTS/git/gitempty.md

# exit if any command fails, including unset variables and pipeline errors
set -euo pipefail

# check if in git repository, aborts if not
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
echo "FATAL ERROR: Not a git repository (or any of the parent directories)" >&2; exit 1; fi

# use remote default branch as local default branch
git remote set-head origin --auto >/dev/null || true

# initialize variables
DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD | sed 's@^refs/remotes/origin/@@')
STARTING_BRANCH=$(git branch --show-current)
STASHED_CHANGES=$(git status --porcelain | wc -l | tr -d ' ')
STASH_RESTORED_STATUS="none"

# abort if in detached HEAD state
[ -n "$STARTING_BRANCH" ] || { echo "can't run @gitempty in detached HEAD state"; exit 1; }

# drop tracking refs for branches deleted on remote and mark their local upstream 'gone'
git fetch --prune origin >/dev/null
# check that the local default branch is an ancestor of the remote default branch
git merge-base --is-ancestor "$DEFAULT_BRANCH" "origin/$DEFAULT_BRANCH" \
  || { echo "can't run @gitempty with diverged $DEFAULT_BRANCH"; exit 1; }

# if uncommitted changes, create a temporary stash
if [ "$STASHED_CHANGES" -gt 0 ]; then git stash push -u -m "gitempty" >/dev/null; fi

# count how many commits local default branch is ahead of remote default branch
FAST_FORWARDED=$(git rev-list --count "$DEFAULT_BRANCH..origin/$DEFAULT_BRANCH")
# switch to the default branch and fast-forward it
git switch "$DEFAULT_BRANCH" >/dev/null
git merge --ff-only "origin/$DEFAULT_BRANCH" >/dev/null

# return to starting branch
git switch "$STARTING_BRANCH" >/dev/null

# if there was a stash, pop it
if git stash list | grep -q "gitempty"; then
  # If stash pop fails due to a conflict, we catch it instead of letting set -e crash us
  if git stash pop >/dev/null; then STASH_RESTORED_STATUS="successfully restored"
  else STASH_RESTORED_STATUS="failed to restore"; fi
fi

# telemetry
echo "--- @gitempty telemetry ---"
echo "shell command status: succeeded"
echo "default local branch: $DEFAULT_BRANCH"
echo "starting and ending branch: $STARTING_BRANCH"
echo "total changes stashed: $STASHED_CHANGES"
echo "total fast-forwarded commits: $FAST_FORWARDED"
echo "stash restored status: $STASH_RESTORED_STATUS"
echo "---------------------------"

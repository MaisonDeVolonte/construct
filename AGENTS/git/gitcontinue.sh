#!/bin/bash
# ================================================
# @file gitcontinue.sh - stash/sync/resume sidecar
# ================================================
# @description
# - sidecar for `@gitcontinue` — stash, fetch, fast-forward, pop
# @see AGENTS.md, AGENTS/templates/git.md, AGENTS/git/gitcontinue.md

set -euo pipefail

# check if in git repository
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "fatal: not a git repository" >&2; exit 2; fi

# check for in-progress git operations
if [ -d ".git/rebase-merge" ] || [ -d ".git/rebase-apply" ] || [ -f ".git/MERGE_HEAD" ] || [ -f ".git/CHERRY_PICK_HEAD" ]; then
  echo "fatal: merge, rebase, or cherry-pick in progress" >&2; exit 2; fi

# query remote to ensure origin/HEAD exists locally
git remote set-head origin --auto >/dev/null 2>&1 || true

# initialize variables
DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo "")
CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "")
STARTING_BRANCH=$CURRENT_BRANCH

# validate branch state
if [ -z "$DEFAULT_BRANCH" ]; then
  echo "fatal: missing remote default branch" >&2; exit 2; fi

if [ -z "$CURRENT_BRANCH" ]; then
  echo "fatal: detached HEAD" >&2; exit 2; fi

# state capture & stash
DIRTY=0
if git status --porcelain 2>/dev/null | grep -q .; then
  DIRTY=1
  git stash push -u -m "auto-stash: @gitcontinue" >/dev/null 2>&1 || {
    echo "fatal: could not stash uncommitted changes" >&2; exit 2;
  }
  # Safety net: the steps between here and the deliberate pop below (fetch/switch/ff)
  # all exit 2 on failure, which would leave the stash orphaned and the tree deceptively
  # clean — silently hiding the user's work. Restore it (or loudly surface it) on any such
  # early exit. Disarmed right before the intended pop so normal success/conflict handling
  # stays in charge.
  restore_stash() {
    if git stash list 2>/dev/null | grep -q "auto-stash: @gitcontinue"; then
      git stash pop >/dev/null 2>&1 \
        || echo "⚠️  @gitcontinue: your work is preserved in git stash — run 'git stash pop' to recover it" >&2
    fi
  }
  trap restore_stash EXIT
fi

# trunk sync
if ! git fetch origin "$DEFAULT_BRANCH" --quiet; then
  echo "fatal: could not fetch origin/$DEFAULT_BRANCH (network or remote error)" >&2; exit 2; fi

# switch to default branch
if [ "$CURRENT_BRANCH" != "$DEFAULT_BRANCH" ]; then
  if ! git switch "$DEFAULT_BRANCH" >/dev/null 2>&1; then
  echo "fatal: git refused to switch to $DEFAULT_BRANCH" >&2; exit 2; fi
  CURRENT_BRANCH=$DEFAULT_BRANCH
fi

LOCAL_COMMIT=$(git rev-parse "$DEFAULT_BRANCH")
REMOTE_COMMIT=$(git rev-parse "origin/$DEFAULT_BRANCH")

# fast-forward only
if [ "$LOCAL_COMMIT" != "$REMOTE_COMMIT" ]; then
  if ! git merge --ff-only "origin/$DEFAULT_BRANCH" >/dev/null 2>&1; then
  echo "fatal: $DEFAULT_BRANCH diverged from origin — recover with @gitfresh" >&2; exit 2; fi
fi

# integration & replay
CONFLICT=0
if [ $DIRTY -eq 1 ]; then
  trap - EXIT   # reached the deliberate pop — hand off to the success/conflict handling below
  # We use || true so the script doesn't instantly exit (set -e) if there's a conflict
  if ! git stash pop >/dev/null 2>&1; then
    CONFLICT=1
  fi
fi

# output telemetry
cat <<EOF

=== @gitcontinue telemetry ===
CHECKS: validated env/state, stashed work, synced origin, fast-forwarded trunk, and restored state
DEFAULT BRANCH: $DEFAULT_BRANCH
STARTING BRANCH: $STARTING_BRANCH
EOF

if [ $CONFLICT -eq 1 ]; then
  cat <<EOF
STATUS: STASH POP CONFLICT DETECTED
ACTION: Trunk synced, but your uncommitted changes conflict. Resolve the conflicts in your editor, then run 'git stash drop' to clear the preserved copy.
==============================
EOF
else
  cat <<EOF
STATUS: SUCCESS
ACTION: Trunk synced and you are ready to continue working on $DEFAULT_BRANCH.
==============================
EOF
fi

# exit with code 1 ONLY if we hit a conflict, signaling to the agent that user action is required
if [ $CONFLICT -eq 1 ]; then
  exit 1
fi

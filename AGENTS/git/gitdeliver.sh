#!/bin/bash
# =========================================================
# @file gitdeliver.sh - atomic stage/commit/push/pr sidecar
# =========================================================
# @description
# - sidecar for `@gitdeliver` — preflight before the atomic-bucket delivery loop
# - github auth preflights through curl + bearer since gh cannot verify tls in the sandbox
# @see AGENTS.md, AGENTS/templates/git.md, AGENTS/git/gitdeliver.md, README.md

set -euo pipefail

# check if in git repository
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "fatal: not a git repository" >&2; exit 1; fi

# check for curl and jq, the two tools every github api step rides on
if ! command -v curl >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
  echo "fatal: curl and jq are required (brew install jq)" >&2; exit 1; fi

# check the github token is present; inside the sandbox it holds the masked sentinel
# the proxy swaps for the real value — outside it holds the real token (curl takes both)
if [ -z "${GH_TOKEN:-}" ]; then
  echo "fatal: GH_TOKEN is not set (see README.md > Settings > Keys)" >&2; exit 1; fi

# prove the token authenticates before the delivery loop starts; bearer auth is the one
# shape the mask proxy can substitute (see README.md > Settings > Keys > GitHub)
AUTH_CODE=$(curl -sS --max-time 15 -o /dev/null -w '%{http_code}' \
  -H "Authorization: Bearer $GH_TOKEN" https://api.github.com/user 2>/dev/null || echo 000)
if [ "$AUTH_CODE" != "200" ]; then
  echo "fatal: github api auth failed (http $AUTH_CODE)" >&2; exit 1; fi

# check for in-progress git operations
if [ -d ".git/rebase-merge" ] || [ -d ".git/rebase-apply" ] || [ -f ".git/MERGE_HEAD" ] || [ -f ".git/CHERRY_PICK_HEAD" ]; then
  echo "fatal: merge, rebase, or cherry-pick in progress" >&2; exit 1; fi

# query remote to ensure origin/HEAD exists locally
git remote set-head origin --auto >/dev/null 2>&1 || true

DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo "")
CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "")
STARTING_BRANCH=$CURRENT_BRANCH

# validate branch state
if [ -z "$DEFAULT_BRANCH" ]; then
  echo "fatal: missing remote default branch" >&2; exit 1; fi

if [ -z "$CURRENT_BRANCH" ]; then
  echo "fatal: detached HEAD" >&2; exit 1; fi

# require uncommitted changes to exist before proceeding
if ! git status --porcelain 2>/dev/null | grep -q .; then
  echo "fatal: working tree clean" >&2; exit 1; fi

# switch to default branch (floating uncommitted changes)
if [ "$CURRENT_BRANCH" != "$DEFAULT_BRANCH" ]; then
  if ! git switch "$DEFAULT_BRANCH" >/dev/null 2>&1; then
  echo "fatal: git refused to switch to $DEFAULT_BRANCH (conflicting histories)" >&2; exit 1; fi
  CURRENT_BRANCH=$DEFAULT_BRANCH
fi

# sync default branch with remote
if ! git fetch origin "$DEFAULT_BRANCH" --quiet; then
  echo "fatal: could not fetch origin/$DEFAULT_BRANCH (network or remote error)" >&2; exit 1; fi

LOCAL_COMMIT=$(git rev-parse "$DEFAULT_BRANCH")
REMOTE_COMMIT=$(git rev-parse "origin/$DEFAULT_BRANCH")

if [ "$LOCAL_COMMIT" != "$REMOTE_COMMIT" ]; then
  if ! git merge --ff-only "origin/$DEFAULT_BRANCH" >/dev/null 2>&1; then
    if ! git diff --quiet || ! git diff --cached --quiet; then
      echo "fatal: could not fast-forward $DEFAULT_BRANCH (uncommitted changes conflict with remote updates – stash, fast-forward, pop, and resolve conflicts locally)" >&2; exit 1;
    else
      echo "fatal: could not fast-forward $DEFAULT_BRANCH (committed changes conflict with remote updates – rebase and resolve conflicts locally)" >&2; exit 1;
    fi
  fi
fi

# unstage all files to give the agent a clean slate for atomic commits
if ! git diff --cached --quiet; then git restore --staged :/ >/dev/null 2>&1; fi

# output telemetry
cat <<EOF

=== @gitdeliver preflight status ===
CHECKS: validated env/state, resolved trunk, floated changes, synced origin, cleared index
DEFAULT BRANCH: $DEFAULT_BRANCH
STARTING BRANCH: $STARTING_BRANCH
READY FOR ATOMIC LOOP
====================================
EOF

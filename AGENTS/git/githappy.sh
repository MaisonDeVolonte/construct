#!/bin/bash
# ====================================================
# @file githappy.sh - version bump/tag/release sidecar
# ====================================================
# @description
# - sidecar for `@githappy` — bumps version, tags, promotes main to production
# @see AGENTS.md, AGENTS/templates/git.md, AGENTS/git/githappy.md

set -euo pipefail

FLAG=${1:-}
if [ "$FLAG" = "--major" ]; then
  TYPE="major"
elif [ "$FLAG" = "--minor" ] || [ -z "$FLAG" ]; then
  TYPE="minor"
else
  echo "fatal: release flag must be '--minor' or '--major'" >&2
  exit 1
fi

# check if in git repository
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "fatal: not a git repository" >&2; exit 1; fi

# check for github cli
if ! command -v gh >/dev/null 2>&1 || ! gh auth status >/dev/null 2>&1; then
  echo "fatal: gh cli missing or unauthenticated" >&2; exit 1; fi

# query remote to ensure origin/HEAD exists locally
git remote set-head origin --auto >/dev/null 2>&1 || true

# initialize variables
DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo "main")
CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "")
PRODUCTION_BRANCH="production"

# validate branch states
if [ -z "$CURRENT_BRANCH" ]; then
  echo "fatal: detached HEAD" >&2; exit 1; fi

if [ "$CURRENT_BRANCH" != "$DEFAULT_BRANCH" ]; then
  echo "fatal: must be on default branch ($DEFAULT_BRANCH) to release" >&2; exit 1; fi

if ! git show-ref --verify --quiet "refs/heads/$PRODUCTION_BRANCH" && ! git ls-remote --exit-code --heads origin "$PRODUCTION_BRANCH" >/dev/null 2>&1; then
  echo "fatal: production branch '$PRODUCTION_BRANCH' does not exist locally or on remote." >&2; exit 1; fi

# ensure no active rebases or merges (fail fast before pushing)
if [ -d ".git/rebase-merge" ] || [ -d ".git/rebase-apply" ] || [ -f ".git/MERGE_HEAD" ] || [ -f ".git/CHERRY_PICK_HEAD" ]; then
  echo "fatal: merge, rebase, or cherry-pick in progress" >&2; exit 1; fi

# ensure clean working tree
if git status --porcelain 2>/dev/null | grep -q .; then
  echo "fatal: working tree has uncommitted changes. run @gitdeliver or @gitcontinue first." >&2; exit 1; fi

# sync default branch with remote
if ! git fetch origin "$DEFAULT_BRANCH" --quiet; then
  echo "fatal: could not fetch origin/$DEFAULT_BRANCH (network or remote error)" >&2; exit 1; fi

LOCAL_COMMIT=$(git rev-parse "$DEFAULT_BRANCH")
REMOTE_COMMIT=$(git rev-parse "origin/$DEFAULT_BRANCH")

if [ "$LOCAL_COMMIT" != "$REMOTE_COMMIT" ]; then
  echo "fatal: local $DEFAULT_BRANCH is out of sync with origin. run @gitcontinue or pull first." >&2; exit 1; fi

# execute npm version bump
echo "=== bumping version ($TYPE) ==="
NEW_VERSION=$(npm version "$TYPE")

if [ "$PRODUCTION_BRANCH" != "" ]; then
  echo "=== merging to $PRODUCTION_BRANCH branch ==="
  # fetch production if it only exists on remote
  if ! git show-ref --verify --quiet "refs/heads/$PRODUCTION_BRANCH"; then
    git fetch origin "$PRODUCTION_BRANCH:$PRODUCTION_BRANCH"
  fi

  git switch "$PRODUCTION_BRANCH"
  git merge --ff-only "$DEFAULT_BRANCH"
  git push origin "$PRODUCTION_BRANCH"
  git switch "$DEFAULT_BRANCH"
fi

echo "=== pushing $NEW_VERSION to origin ==="
git push origin "$DEFAULT_BRANCH" --follow-tags

echo "=== creating github release $NEW_VERSION ==="
gh release create "$NEW_VERSION" --generate-notes --title "Release $NEW_VERSION"

cat <<EOF

=== @githappy release complete ===
BUMPED: $NEW_VERSION
BRANCH: $DEFAULT_BRANCH
EOF

if [ "$PRODUCTION_BRANCH" != "" ]; then
  echo "PROMOTED: merged to $PRODUCTION_BRANCH"
fi

cat <<EOF
STATUS: pushed and released on github
==================================
EOF

#!/bin/bash
# =============================================
# @file gitgud.sh - stale-pr ci refresh sidecar
# =============================================
# @description
# - sidecar for `@gitgud` — re-runs ci on a stale pr against the default branch
# @see AGENTS.md, AGENTS/templates/git.md, AGENTS/git/gitgud.md

set -euo pipefail

WATCH="false"
for arg in "$@"; do
  case "$arg" in
    --watch) WATCH="true" ;;
    *) echo "fatal: unknown argument '$arg' (the only flag is --watch)" >&2; exit 1;;
  esac
done

# GUARDS

# check if in git repository
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "fatal: not a git repository" >&2; exit 1; fi

# check for github cli
if ! command -v gh >/dev/null 2>&1 || ! gh auth status >/dev/null 2>&1; then
  echo "fatal: gh cli missing or unauthenticated" >&2; exit 1; fi

# check for in-progress git operations
if [ -d ".git/rebase-merge" ] || [ -d ".git/rebase-apply" ] || [ -f ".git/MERGE_HEAD" ] || [ -f ".git/CHERRY_PICK_HEAD" ]; then
  echo "fatal: merge, rebase, or cherry-pick in progress" >&2; exit 1; fi

# query remote to ensure origin/HEAD exists locally
git remote set-head origin --auto >/dev/null 2>&1 || true

DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo "")
if [ -z "$DEFAULT_BRANCH" ]; then
  echo "fatal: missing remote default branch" >&2; exit 1; fi

# always target the open pr for the branch you're sitting on
PR_NUMBER=$(gh pr view --json number -q '.number' 2>/dev/null || echo "")
if [ -z "$PR_NUMBER" ]; then
  echo "fatal: no open pr for the current branch (run @gitgud from the pr branch)" >&2; exit 1; fi

# pull the pr's live state in one query (tab-separated so we can read it into fields)
PR_INFO=$(gh pr view "$PR_NUMBER" --json state,headRefName,baseRefName,mergeStateStatus,url \
  -q '[.state, .headRefName, .baseRefName, .mergeStateStatus, .url] | @tsv' 2>/dev/null || echo "")
if [ -z "$PR_INFO" ]; then
  echo "fatal: pr #$PR_NUMBER not found" >&2; exit 1; fi
IFS=$'\t' read -r PR_STATE PR_HEAD PR_BASE PR_MERGESTATE PR_URL <<< "$PR_INFO"

if [ "$PR_STATE" != "OPEN" ]; then
  echo "fatal: pr #$PR_NUMBER is $PR_STATE (only open prs can be redelivered)" >&2; exit 1; fi

# a conflicted pr can't be updated through the api — the base merge would fail
if [ "$PR_MERGESTATE" = "DIRTY" ]; then
  echo "fatal: pr #$PR_NUMBER conflicts with $DEFAULT_BRANCH (resolve locally; ci won't clear on its own)" >&2; exit 1; fi

# sync the branches we compare; forks aren't supported (their head isn't on origin)
if ! git fetch origin "$DEFAULT_BRANCH" "$PR_HEAD" --quiet 2>/dev/null; then
  echo "fatal: could not fetch $PR_HEAD or $DEFAULT_BRANCH from origin (same-repo prs only)" >&2; exit 1; fi

# how many commits the trunk has that this pr hasn't absorbed — the staleness signal
BEHIND_COUNT=$(git rev-list --count "origin/$PR_HEAD..origin/$DEFAULT_BRANCH" 2>/dev/null || echo "0")

# nothing stale to fix → a red run here is a real failure, not a base problem
if [ "$BEHIND_COUNT" -eq 0 ]; then
  echo "fatal: pr #$PR_NUMBER already contains all of $DEFAULT_BRANCH — any ci failure is real, read the logs at $PR_URL" >&2; exit 1; fi

# EXECUTION

# watch mode needs the current top run so it can spot the fresh one after re-triggering
if [ "$WATCH" = "true" ]; then
  OLD_RUN_ID=$(gh run list --branch "$PR_HEAD" --limit 1 --json databaseId -q '.[0].databaseId // ""' 2>/dev/null || echo "")
fi

# merge the fresh trunk into the pr branch → fires a synchronize event → ci rebuilds against the current trunk
if ! gh pr update-branch "$PR_NUMBER" >/dev/null 2>&1; then
  echo "fatal: could not update pr #$PR_NUMBER branch (conflicts or protected branch — resolve locally)" >&2; exit 1; fi
RESULT="redelivered"

# the default returns here; --watch follows the fresh run to green or red
if [ "$WATCH" = "true" ]; then
  # wait for the fresh run to register as a new id at the top of the list
  RUN_ID="$OLD_RUN_ID"
  ATTEMPTS=0
  while [ "$RUN_ID" = "$OLD_RUN_ID" ] && [ "$ATTEMPTS" -lt 15 ]; do
    sleep 2
    RUN_ID=$(gh run list --branch "$PR_HEAD" --limit 1 --json databaseId -q '.[0].databaseId // ""' 2>/dev/null || echo "$OLD_RUN_ID")
    ATTEMPTS=$((ATTEMPTS + 1))
  done
  if [ "$RUN_ID" = "$OLD_RUN_ID" ] || [ -z "$RUN_ID" ]; then
    echo "fatal: redelivered pr #$PR_NUMBER but a fresh ci run never registered (check $PR_URL)" >&2; exit 1; fi

  # --exit-status turns a red run into a nonzero exit
  if gh run watch "$RUN_ID" --exit-status >/dev/null 2>&1; then
    RESULT="green"
  else
    RESULT="red"
  fi
fi

# TELEMETRY

cat <<EOF
=== @gitgud redelivery ===
PR: #$PR_NUMBER ($PR_HEAD → $PR_BASE)
ABSORBED: $BEHIND_COUNT commit(s) from $DEFAULT_BRANCH
ACTION: merged $DEFAULT_BRANCH into $PR_HEAD (synchronize event)
RESULT: $RESULT
URL: $PR_URL
==========================
EOF

# a red run is a real failure now that the base is fresh
if [ "$RESULT" = "red" ]; then
  echo "fatal: ci still red after redelivery — the failure is real, inspect: $PR_URL" >&2
  exit 1
fi

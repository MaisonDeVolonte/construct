#!/bin/bash
# ===================================================
# @file gitfresh.sh - hard-reset measure and handover
# ===================================================
# @description
# - sidecar for `@gitfresh` — measures what a reset would cost, then hands every command over
# - read-only: it now backs nothing up either, since `git stash` joined the deny floor
# - the backup stash leads the handover, so the user's first pasted line is the recoverable one
# - names every commit and branch the reset destroys before the user runs a thing
# - measuring after the fetch is what makes the discarded/gained counts describe the real remote
# @see AGENTS.md, AGENTS/templates/git.md, AGENTS/git/gitfresh.md, AGENTS/git/handover.sh

set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)
if [ ! -f "$HERE/handover.sh" ]; then
  echo "fatal: no AGENTS/git/handover.sh beside this sidecar" >&2; exit 1; fi
# shellcheck source=./handover.sh
. "$HERE/handover.sh"

require_repo

DEFAULT_BRANCH=$(git_default_branch)
STARTING_BRANCH=$(git_current_branch)

if [ -z "$DEFAULT_BRANCH" ]; then
  echo "fatal: missing remote default branch" >&2; exit 1; fi

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
STASH_NAME="gitfresh-$TIMESTAMP"
UNTRACKED_COUNT=$(git status --porcelain=v1 | grep -cE '^\?\?' || true)
MODIFIED_COUNT=$(git status --porcelain=v1 | grep -cE '^[ MADRCU]' || true)
ALL_LOCAL_BRANCHES=$(git for-each-ref --format='%(refname:short)' refs/heads/ \
  | grep -vx "$DEFAULT_BRANCH" || true)

# an in-progress operation changes which commands the handover has to open with
OP_IN_PROGRESS=none
if [ -d ".git/rebase-merge" ] || [ -d ".git/rebase-apply" ]; then OP_IN_PROGRESS=rebase
elif [ -f ".git/MERGE_HEAD" ]; then OP_IN_PROGRESS=merge
elif [ -f ".git/CHERRY_PICK_HEAD" ]; then OP_IN_PROGRESS=cherry-pick; fi

FETCH_ERR=""
if ! FETCH_ERR=$(git fetch --prune origin --quiet 2>&1); then
  echo "fatal: could not fetch origin" >&2
  echo "$FETCH_ERR" >&2
  exit 1
fi

# measured after the fetch, so these describe what the reset actually costs against origin today
DISCARDED_COMMITS=$(git rev-list --count "origin/$DEFAULT_BRANCH..$DEFAULT_BRANCH" 2>/dev/null || echo 0)
GAINED_COMMITS=$(git rev-list --count "$DEFAULT_BRANCH..origin/$DEFAULT_BRANCH" 2>/dev/null || echo 0)
PENDING_BRANCH_COUNT=$(printf '%s' "$ALL_LOCAL_BRANCHES" | grep -c . || true)

telemetry_open gitfresh
telemetry_line "default branch" "$DEFAULT_BRANCH"
telemetry_line "current branch" "${STARTING_BRANCH:-detached}"
telemetry_line "operation in progress" "$OP_IN_PROGRESS"
telemetry_line "untracked files at risk" "$UNTRACKED_COUNT"
telemetry_line "modifications at risk" "$MODIFIED_COUNT"
telemetry_line "commits the reset discards" "$DISCARDED_COMMITS"
telemetry_line "commits the reset gains" "$GAINED_COMMITS"
telemetry_line "branches pending deletion" "${PENDING_BRANCH_COUNT:-0}"
telemetry_line "pending branch names" \
  "$(printf '%s' "$ALL_LOCAL_BRANCHES" | paste -sd, - | sed 's/,/, /g')"

handover_open gitfresh
handover_note "every line below is refused as a tool call — run them yourself, in this order"
handover_note "the stash is first on purpose: it is the only step that can be undone"
if git_is_dirty; then
  handover_cmd "git stash push -a -m '$STASH_NAME'"
fi
if [ "$OP_IN_PROGRESS" != "none" ]; then
  handover_cmd "git $OP_IN_PROGRESS --abort"
fi
handover_cmd "git switch -f $DEFAULT_BRANCH"
handover_cmd "git clean -fd"
handover_cmd "git reset --hard origin/$DEFAULT_BRANCH"
for branch in $ALL_LOCAL_BRANCHES; do
  handover_cmd "git branch -D $branch"
done
if git_is_dirty; then
  handover_note "recover the backup afterwards with: git stash pop"
fi
block_close

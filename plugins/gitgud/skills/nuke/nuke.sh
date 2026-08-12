#!/bin/bash
# ===============================================
# @file nuke.sh - hard-reset measure and handover
# ===============================================
# @description
# PAIR
# - sidecar for `/gitgud:nuke` — measures what a reset would cost, then splits it into two blocks
# - for a workspace that is broken, conflicted, or too desynced to recover by hand
# - it names every commit, file and branch the reset destroys before the user runs a thing
# SIDECAR
# - read-only itself: it destroys nothing and backs nothing up, it only prices the reset
# - measuring after the fetch is what makes the discarded and gained counts describe the remote
# - the doc reads `git-audit.sh` first, so the branch triage is already on screen
# TRIGGER
# - the backup gets its own block, so the recoverable step never rides on a full-block paste
# - the trigger runs that stash and then proves it landed, since the rest of the run rests on it
# - `-u` and not `-a`, since a reset never touches ignored files and stashing them buys nothing
# - clean, reset, switch -f and branch deletes stay denied, so the user runs every one
# - the backup running first is the whole point: a handover the user half-pastes still has it
# @see plugins/gitgud/skills/nuke/SKILL.md, plugins/gitgud/shared/triage.sh, plugins/gitgud/skills/backup/SKILL.md, plugins/gitgud/shared/handover.sh, .claude/skills/validate-skills/SKILL.md

set -euo pipefail

# the doc is read only after this has already run, so help is refused here or not at all; the doc's
# own '## Help' section owns the output, which is why this prints a marker rather than a usage text
case " $* " in *" --help "*|*" -h "*) echo "help: requested"; exit 0;; esac

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)
SHARED=$(cd "$HERE/../../shared" 2>/dev/null && pwd || true)
if [ ! -f "$SHARED/handover.sh" ]; then
  echo "fatal: no plugins/gitgud/shared/handover.sh reachable from this sidecar" >&2; exit 1; fi
# shellcheck source=../../shared/handover.sh
. "$SHARED/handover.sh"

require_repo

DEFAULT_BRANCH=$(git_default_branch)
STARTING_BRANCH=$(git_current_branch)

if [ -z "$DEFAULT_BRANCH" ]; then
  echo "fatal: missing remote default branch" >&2; exit 1; fi

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
STASH_NAME="git-fresh-$TIMESTAMP"
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

telemetry_open gitgud:nuke
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

# the backup is split into its own block because it is the only step here that adds safety; the
# trigger runs it, so the one recoverable line never depends on the user pasting the block whole
if git_is_dirty; then
  trigger_open gitgud:nuke
  handover_note "the trigger runs this itself, then proves the stash exists before handing over"
  handover_cmd "git stash push -u -m '$STASH_NAME'"
  block_close
fi

handover_open gitgud:nuke
handover_note "every line below is refused as a tool call — run them yourself, in this order"
if git_is_dirty; then
  handover_note "do NOT run these until the backup above reports a stash entry named $STASH_NAME"
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

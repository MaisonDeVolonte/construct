#!/bin/bash
# ===========================================
# @file prune.sh - post-merge cleanup sidecar
# ===========================================
# @description
# PAIR
# - sidecar for `/gitgud:prune` — finds spent branches, then hands the cleanup commands over
# - typically run post-merge, but safe anytime, since nothing in the pair deletes a branch
# SIDECAR
# - read-only apart from `fetch --prune`, which deletes no local branch and writes no tracked file
# - the trunk sync is delegated whole: the doc's fence runs continue.sh first, every invocation
# - a run that needed a sync ends on the trunk, which is where continue's own doctrine lands it
# - classifies each local branch as gone, merged, or live, so the handover deletes only the spent
# - emits `-d` or `-D` to match, since `-d` consults the same patch-id read a rebase already fooled
# - a rebased copy trunk later edited fails the tree read, so a patch-id read also earns `-D`
# - a gone branch that is neither merged, absorbed nor patch-equivalent is kept, never offered
# - `production` is excluded by name, since a release branch reads merged and behind by design
# TRIGGER
# - runs `triage.sh` last, whose local/remote/ghost/zombie split catches the rebased ones
# - branch deletes stay denied and handed over; the sync's stash bracket belongs to continue.sh
# @see plugins/gitgud/skills/prune/SKILL.md, plugins/gitgud/shared/triage.sh, plugins/gitgud/shared/handover.sh, .claude/skills/validate-skills/SKILL.md

set -euo pipefail

# the doc's '## Help' owns the output, so help prints a marker here instead of usage text
case " $* " in *" --help "*|*" -h "*) echo "help: requested"; exit 0;; esac

# the smoke case proves this file parses and its guards return, without running a skill step
case " $* " in *" --test "*) echo "test: ok"; exit 0;; esac

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)
SHARED=$(cd "$HERE/../../shared" 2>/dev/null && pwd || true)
if [ ! -f "$SHARED/handover.sh" ]; then
  echo "fatal: no plugins/gitgud/shared/handover.sh reachable from this sidecar" >&2; exit 1; fi
# shellcheck source=../../shared/handover.sh
. "$SHARED/handover.sh"

# this skill hands over branch deletions, so any argument stops it rather than being ignored
if [ "$#" -gt 0 ]; then
  echo "fatal: /gitgud:prune takes no arguments; every branch is classified from the tree" >&2
  exit 1
fi

require_repo
require_no_op_in_progress

DEFAULT_BRANCH=$(git_default_branch)
STARTING_BRANCH=$(git_current_branch)

# a release branch looks spent by design, so it is excluded by name (see the doc's ignored row)
PRODUCTION_BRANCH="production"

if [ -z "$DEFAULT_BRANCH" ]; then
  echo "fatal: missing remote default branch" >&2; exit 1; fi
if [ -z "$STARTING_BRANCH" ]; then
  echo "fatal: detached HEAD" >&2; exit 1; fi

# --prune drops tracking refs for branches deleted on the remote, marking their local counterparts
# 'gone' below; a sandboxed fetch exits nonzero after its objects land, so only a stale ref fails
FETCH_RC=0
git fetch --prune origin --quiet 2>/dev/null || FETCH_RC=$?
if ! git rev-parse --verify --quiet "origin/$DEFAULT_BRANCH" >/dev/null; then
  echo "fatal: origin/$DEFAULT_BRANCH unresolved after fetch (exit $FETCH_RC)" >&2
  exit 1
fi

BEHIND=$(git rev-list --count "$DEFAULT_BRANCH..origin/$DEFAULT_BRANCH" 2>/dev/null || echo 0)
AHEAD=$(git rev-list --count "origin/$DEFAULT_BRANCH..$DEFAULT_BRANCH" 2>/dev/null || echo 0)

# a branch is spent when its remote is gone or trunk holds every commit; the rest is live work
GONE_BRANCHES=$(git for-each-ref --format='%(refname:short) %(upstream:track)' refs/heads/ \
  | awk '$2 == "[gone]" { print $1 }' \
  | grep -vx "$DEFAULT_BRANCH" | grep -vx "$PRODUCTION_BRANCH" || true)
MERGED_BRANCHES=$(git branch --merged "origin/$DEFAULT_BRANCH" --format='%(refname:short)' \
  | grep -vx "$DEFAULT_BRANCH" | grep -vx "$PRODUCTION_BRANCH" || true)

SPENT_BRANCHES=$(printf '%s\n%s\n' "$GONE_BRANCHES" "$MERGED_BRANCHES" | grep -v '^$' | sort -u || true)
SPENT_COUNT=$(printf '%s' "$SPENT_BRANCHES" | grep -c . || true)

# -d needs trunk to contain the tip, so a rebased branch earns -D by its tree or its patch-ids
DELETE_SAFE=""
DELETE_FORCE=""
KEEP_BRANCHES=""
for branch in $SPENT_BRANCHES; do
  if printf '%s\n' "$MERGED_BRANCHES" | grep -qx "$branch"; then
    DELETE_SAFE="$DELETE_SAFE $branch"
  elif [ "$(is_absorbed "origin/$DEFAULT_BRANCH" "$branch")" = "yes" ]; then
    DELETE_FORCE="$DELETE_FORCE $branch"
  elif CHERRY=$(git cherry "origin/$DEFAULT_BRANCH" "$branch" 2>/dev/null) \
    && ! printf '%s\n' "$CHERRY" | grep -q '^+'; then
    # a failed cherry read prints nothing, so its exit code gates the delete and keeps the branch
    DELETE_FORCE="$DELETE_FORCE $branch"
  else
    KEEP_BRANCHES="$KEEP_BRANCHES $branch"
  fi
done
DELETE_COUNT=$(printf '%s' "$DELETE_SAFE $DELETE_FORCE" | tr ' ' '\n' | grep -c . || true)
LIVE_COUNT=$(git for-each-ref --format='%(refname:short)' refs/heads/ \
  | grep -vx "$DEFAULT_BRANCH" | grep -vx "$PRODUCTION_BRANCH" | grep -c . || true)
LIVE_COUNT=$((LIVE_COUNT - SPENT_COUNT))

telemetry_open gitgud:prune
telemetry_line "default branch" "$DEFAULT_BRANCH"
telemetry_line "current branch" "$STARTING_BRANCH"
telemetry_line "trunk behind origin" "$BEHIND"
telemetry_line "trunk ahead of origin" "$AHEAD"
SYNC_STATE="not needed"
if [ "$BEHIND" -gt 0 ]; then SYNC_STATE="needed (continue's block above owns it)"; fi
telemetry_line "trunk sync" "$SYNC_STATE"
telemetry_line "spent branches" "${SPENT_COUNT:-0}"
telemetry_line "live branches" "${LIVE_COUNT:-0}"
telemetry_line "spent branch names" "$(printf '%s' "$SPENT_BRANCHES" | paste -sd, - | sed 's/,/, /g')"
telemetry_line "deletable with -d" "$(printf '%s' "${DELETE_SAFE# }" | sed 's/ /, /g')"
telemetry_line "deletable with -D (absorbed or patch-equal)" "$(printf '%s' "${DELETE_FORCE# }" | sed 's/ /, /g')"
telemetry_line "kept, unmerged, unabsorbed, patch-distinct" "$(printf '%s' "${KEEP_BRANCHES# }" | sed 's/ /, /g')"

handover_open gitgud:prune
if [ "$AHEAD" -gt 0 ]; then
  handover_note "$DEFAULT_BRANCH has $AHEAD commit(s) origin does not — resolve before cleaning up"
elif [ "${DELETE_COUNT:-0}" -eq 0 ]; then
  handover_note "nothing to clean up — no branch is safe to delete"
  if [ -n "$KEEP_BRANCHES" ]; then
    handover_note "kept as real work:${KEEP_BRANCHES} — $DEFAULT_BRANCH holds neither its tree nor its patches"
  fi
else
  handover_note "cleanup — yours to run in order; every delete is denied to the agent by design"
  # -d refuses a branch trunk does not already contain, which is the safety this list relies on
  for branch in $DELETE_SAFE; do
    handover_cmd "git branch -d $branch"
  done
  # -D skips that check, so it is spent only where the tree or patch-id read above proved it safe
  for branch in $DELETE_FORCE; do
    handover_cmd "git branch -D $branch"
  done
  if [ -n "$KEEP_BRANCHES" ]; then
    handover_note "kept as real work:${KEEP_BRANCHES} — trunk holds neither its tree nor its patches, so not offered"
  fi
fi
block_close

# triage runs here because block-untracked-exec denied the doc's `bash "$T"`; set -e fails on it
echo "=== /gitgud:prune triage ==="
"$SHARED/triage.sh"

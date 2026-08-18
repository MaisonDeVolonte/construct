#!/bin/bash
# ==========================================================
# @file continue.sh - trunk sync measure, handover, artifact
# ==========================================================
# @description
# PAIR
# - sidecar for `/gitgud:continue` — measures the trunk delta, then emits the sync for the trigger
# - pause work, sync the trunk, resume: the sync always ends on the trunk, never a feature branch
# SAFETY
# - read-only contract: never stashes, switches, merges, or pops itself
# - those four stay a TRIGGER block instead, so each one is a gated tool call, not a script line
# - hands the sync over instead of naming it on four shapes: diverged, an incoming sandbox-denied
# - path, a local edit at a sandbox-denied path, or a path both incoming and locally dirty at once
# - the last one is the silent-loss shape: a merge writes that path first, stash pop then refuses
# - to restore over what's already there, and the edit is stranded inside the stash unseen
# ARTIFACT
# - every run, clean or refused, writes one manifest to `.construct/gitgud/continue/`
# @see plugins/gitgud/skills/continue/SKILL.md, plugins/gitgud/skills/backup/SKILL.md,
#      plugins/gitgud/shared/handover.sh, .claude/skills/validate-skills/SKILL.md

set -euo pipefail

# the doc is read only after this has already run, so help is refused here or not at all; the doc's
# own '## Help' section owns the output, which is why this prints a marker rather than a usage text
case " $* " in *" --help "*|*" -h "*) echo "help: requested"; exit 0;; esac

# the smoke case proves this file parses and its guards return; /test-skills reads the sources,
# the @see paths and the tool guards statically, so nothing here runs a step of the skill
case " $* " in *" --test "*) echo "test: ok"; exit 0;; esac

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)
SHARED=$(cd "$HERE/../../shared" 2>/dev/null && pwd || true)
if [ ! -f "$SHARED/handover.sh" ]; then
  echo "fatal: no plugins/gitgud/shared/handover.sh reachable from this sidecar" >&2; exit 1; fi
# shellcheck source=../../shared/handover.sh
. "$SHARED/handover.sh"

# a typo'd flag must stop the run rather than be ignored, since the handover below syncs a branch;
# the doc declares no argument, and the branch it continues is the one already checked out
if [ "$#" -gt 0 ]; then
  echo "fatal: /gitgud:continue takes no arguments; it continues the branch you are on" >&2
  exit 1
fi

require_repo
require_no_op_in_progress

DEFAULT_BRANCH=$(git_default_branch)
CURRENT_BRANCH=$(git_current_branch)

if [ -z "$DEFAULT_BRANCH" ]; then
  echo "fatal: missing remote default branch" >&2; exit 1; fi
if [ -z "$CURRENT_BRANCH" ]; then
  echo "fatal: detached HEAD" >&2; exit 1; fi

# fetch before measuring, or every count below describes a stale remote
FETCH_ERR=""
if ! FETCH_ERR=$(git fetch origin "$DEFAULT_BRANCH" --quiet 2>&1); then
  echo "fatal: could not fetch origin/$DEFAULT_BRANCH" >&2
  echo "$FETCH_ERR" >&2
  exit 1
fi

DIRTY=0
if git_is_dirty; then DIRTY=1; fi
CHANGED_FILES=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')

# ahead and behind are separate counts on purpose: a trunk that is only behind fast-forwards
# cleanly, and calling that "diverged" is what sent an earlier run at the destructive path
BEHIND=$(git rev-list --count "$DEFAULT_BRANCH..origin/$DEFAULT_BRANCH" 2>/dev/null || echo 0)
AHEAD=$(git rev-list --count "origin/$DEFAULT_BRANCH..$DEFAULT_BRANCH" 2>/dev/null || echo 0)

# ==============
# COLLISION CHECKS
# ==============
# incoming is whatever the fast-forward would write; local is whatever `stash -u` would sweep
INCOMING_PATHS=""
INCOMING_PROTECTED=""
if [ "$BEHIND" -gt 0 ]; then
  INCOMING_PATHS=$(git diff --name-only "$DEFAULT_BRANCH..origin/$DEFAULT_BRANCH" 2>/dev/null)
  INCOMING_PROTECTED=$(printf '%s\n' "$INCOMING_PATHS" | protected_paths | paste -sd, - | sed 's/,/, /g')
fi

LOCAL_PATHS=$(git status --porcelain=v1 --no-renames 2>/dev/null | cut -c4-)
LOCAL_PROTECTED=$(printf '%s\n' "$LOCAL_PATHS" | protected_paths | paste -sd, - | sed 's/,/, /g')

# the join between incoming and local dirty: a merge writes it first, pop then refuses to restore
COLLIDING=""
if [ "$BEHIND" -gt 0 ] && [ -n "$LOCAL_PATHS" ]; then
  COLLIDING=$(comm -12 <(printf '%s\n' "$INCOMING_PATHS" | sort -u) <(printf '%s\n' "$LOCAL_PATHS" | sort -u) \
    | grep -v '^$' | paste -sd, - | sed 's/,/, /g' || true)
fi

NEEDS_MOVE=0
if [ "$CURRENT_BRANCH" != "$DEFAULT_BRANCH" ] || [ "$BEHIND" -gt 0 ]; then NEEDS_MOVE=1; fi

if [ "$AHEAD" -gt 0 ]; then SYNC_STATE="diverged"
elif [ -n "$COLLIDING" ]; then SYNC_STATE="colliding, the sync is yours to run"
elif [ -n "$INCOMING_PROTECTED" ]; then SYNC_STATE="behind, but the sync is yours to run"
elif [ -n "$LOCAL_PROTECTED" ] && [ "$DIRTY" -eq 1 ] && [ "$NEEDS_MOVE" -eq 1 ]; then
  SYNC_STATE="behind, but the sync is yours to run"
elif [ "$NEEDS_MOVE" -eq 0 ]; then SYNC_STATE="up to date"
else SYNC_STATE="behind, fast-forwards cleanly"; fi

telemetry_open gitgud:continue
telemetry_line "default branch" "$DEFAULT_BRANCH"
telemetry_line "current branch" "$CURRENT_BRANCH"
telemetry_line "uncommitted files" "$CHANGED_FILES"
telemetry_line "trunk behind origin" "$BEHIND"
telemetry_line "trunk ahead of origin" "$AHEAD"
telemetry_line "sync state" "$SYNC_STATE"
telemetry_line "sandbox-denied incoming paths" "${INCOMING_PROTECTED:-none}"
telemetry_line "sandbox-denied local paths" "${LOCAL_PROTECTED:-none}"
telemetry_line "colliding paths" "${COLLIDING:-none}"

# ==============
# ARTIFACT
# ==============
STAMP=$(date +%Y-%m-%d-%H%M%S)
DEST=".construct/gitgud/continue"
mkdir -p "$DEST"
ARTIFACT="$DEST/$STAMP.txt"
{
  printf 'gitgud-continue %s\n' "$STAMP"
  printf 'default branch: %s\n' "$DEFAULT_BRANCH"
  printf 'current branch: %s\n' "$CURRENT_BRANCH"
  printf 'uncommitted files: %s\n' "$CHANGED_FILES"
  printf 'trunk behind origin: %s\n' "$BEHIND"
  printf 'trunk ahead of origin: %s\n' "$AHEAD"
  printf 'sync state: %s\n' "$SYNC_STATE"
  printf 'sandbox-denied incoming paths: %s\n' "${INCOMING_PROTECTED:-none}"
  printf 'sandbox-denied local paths: %s\n' "${LOCAL_PROTECTED:-none}"
  printf 'colliding paths: %s\n' "${COLLIDING:-none}"
} > "$ARTIFACT"
telemetry_line "artifact" "$ARTIFACT"

# the stash only earns its place when something has to move underneath it; a dirty tree with
# nothing to switch to and nothing to fast-forward would otherwise get a push/pop that is a no-op
handover_open gitgud:continue
if [ "$AHEAD" -gt 0 ]; then
  handover_note "$DEFAULT_BRANCH has $AHEAD local commit(s) origin does not — resolve before syncing"
  handover_note "inspect them first: git log --oneline origin/$DEFAULT_BRANCH..$DEFAULT_BRANCH"
elif [ "$NEEDS_MOVE" -eq 0 ]; then
  handover_note "nothing to do — you are on $DEFAULT_BRANCH and in sync with origin"
  if [ "$DIRTY" -eq 1 ]; then
    handover_note "your $CHANGED_FILES uncommitted file(s) are untouched, which is the point"
  fi
elif [ -n "$COLLIDING" ]; then
  handover_note "DO NOT RUN THESE — incoming touches a path you have uncommitted: $COLLIDING"
  handover_note "a merge would write it first, then stash pop would refuse to restore yours"
  handover_note "resolve the collision by hand, then re-run /gitgud:continue"
elif [ -n "$INCOMING_PROTECTED" ] || [ -n "$LOCAL_PROTECTED" ]; then
  handover_note "DO NOT RUN THESE — the sync writes paths no sandboxed command can:"
  handover_note "incoming: ${INCOMING_PROTECTED:-none}"
  handover_note "local: ${LOCAL_PROTECTED:-none}"
  handover_note "paste the block into your own terminal instead, in the order printed"
  if [ "$DIRTY" -eq 1 ]; then
    handover_cmd "git stash push -u -m 'auto-stash: /gitgud:continue'"
  fi
  if [ "$CURRENT_BRANCH" != "$DEFAULT_BRANCH" ]; then
    handover_cmd "git switch $DEFAULT_BRANCH"
  fi
  if [ "$BEHIND" -gt 0 ]; then
    handover_cmd "git merge --ff-only origin/$DEFAULT_BRANCH"
  fi
  if [ "$DIRTY" -eq 1 ]; then
    handover_cmd "git stash pop"
  fi
else
  handover_note "the trigger runs these in order, stopping at the first non-zero exit"
  if [ "$DIRTY" -eq 1 ]; then
    handover_cmd "git stash push -u -m 'auto-stash: /gitgud:continue'"
  fi
  if [ "$CURRENT_BRANCH" != "$DEFAULT_BRANCH" ]; then
    handover_cmd "git switch $DEFAULT_BRANCH"
  fi
  if [ "$BEHIND" -gt 0 ]; then
    handover_cmd "git merge --ff-only origin/$DEFAULT_BRANCH"
  fi
  if [ "$DIRTY" -eq 1 ]; then
    handover_cmd "git stash pop"
  fi
fi
block_close

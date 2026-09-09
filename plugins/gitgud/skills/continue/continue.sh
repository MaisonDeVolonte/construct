#!/bin/bash
# ==========================================================
# @file continue.sh - trunk sync measure, handover, artifact
# ==========================================================
# @description
# PAIR
# - sidecar for `/gitgud:continue` — measures the trunk delta, then emits the sync for the trigger
# - pause work, sync the trunk, resume: the sync always ends on the trunk, never a feature branch
# MEASURE
# - the delta is read over the rest api, so no measurement depends on a command that writes .git
# - a sandboxed `git fetch` exits 255 on `.git/FETCH_HEAD` after the objects have already landed,
# - so its exit code is recorded rather than trusted, and the tracking ref is verified instead
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
require_tools curl jq

if [ -z "${GH_TOKEN_OPERATOR:-}" ]; then
  echo "fatal: GH_TOKEN_OPERATOR is not set (see README.md > Settings > Keys)" >&2; exit 1; fi

DEFAULT_BRANCH=$(git_default_branch)
CURRENT_BRANCH=$(git_current_branch)

if [ -z "$DEFAULT_BRANCH" ]; then
  echo "fatal: missing remote default branch" >&2; exit 1; fi
if [ -z "$CURRENT_BRANCH" ]; then
  echo "fatal: detached HEAD" >&2; exit 1; fi

# ==============
# REMOTE READ
# ==============
# the remote head is read over the api, so measuring never depends on a command that writes .git
REMOTE_URL=$(git remote get-url origin 2>/dev/null || true)
REPO_SLUG=$(printf '%s' "$REMOTE_URL" | sed -e 's#^.*github\.com[:/]##' -e 's#\.git$##')
if [ -z "$REPO_SLUG" ]; then
  echo "fatal: origin is not a github remote, so the api cannot measure the delta" >&2; exit 1; fi

GITHUB_API="https://api.github.com"
github_api() {
  curl -sS --max-time 15 \
    -H "Authorization: Bearer $GH_TOKEN_OPERATOR" \
    -H "Accept: application/vnd.github+json" \
    "$@"
}

LOCAL_SHA=$(git rev-parse "$DEFAULT_BRANCH" 2>/dev/null || true)
if [ -z "$LOCAL_SHA" ]; then
  echo "fatal: no local $DEFAULT_BRANCH to measure against origin" >&2; exit 1; fi

REMOTE_SHA=$(github_api "$GITHUB_API/repos/$REPO_SLUG/git/ref/heads/$DEFAULT_BRANCH" 2>/dev/null \
  | jq -r '.object.sha // empty')
if [ -z "$REMOTE_SHA" ]; then
  echo "fatal: could not read origin/$DEFAULT_BRANCH over the api" >&2; exit 1; fi

DIRTY=0
if git_is_dirty; then DIRTY=1; fi
CHANGED_FILES=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')

# ==============
# TRUNK DELTA
# ==============
# ahead and behind stay separate counts, since a trunk only behind fast-forwards cleanly
# an earlier run called that case "diverged" and took the destructive path
COMPARE=$(github_api \
  "$GITHUB_API/repos/$REPO_SLUG/compare/$LOCAL_SHA...$REMOTE_SHA" 2>/dev/null || true)
# a 404 body carries its own `.status` of "404", so presence of `.ahead_by` is the real gate
CMP_AHEAD=$(printf '%s' "$COMPARE" | jq -r '.ahead_by // empty' 2>/dev/null || true)

if [ -n "$CMP_AHEAD" ]; then
  # `ahead_by` counts what the head carries over the base, so remote-ahead reads as our behind
  CMP_STATUS=$(printf '%s' "$COMPARE" | jq -r '.status // empty')
  BEHIND="$CMP_AHEAD"
  AHEAD=$(printf '%s' "$COMPARE" | jq -r '.behind_by // 0')
else
  # a miss means origin never saw the local sha, which only an unpushed local commit explains
  CMP_STATUS="unknown to origin"
  BEHIND=0
  AHEAD=$(git rev-list --count "$REMOTE_SHA..$DEFAULT_BRANCH" 2>/dev/null || echo 1)
fi

# ==============
# COLLISION CHECKS
# ==============
# incoming is whatever the fast-forward would write; local is whatever `stash -u` would sweep
INCOMING_PATHS=""
INCOMING_PROTECTED=""
INCOMING_TRUNCATED=0
if [ "$BEHIND" -gt 0 ]; then
  INCOMING_PATHS=$(printf '%s' "$COMPARE" | jq -r '.files[]?.filename // empty')
  INCOMING_PROTECTED=$(printf '%s\n' "$INCOMING_PATHS" | protected_paths | paste -sd, - | sed 's/,/, /g')
  # compare caps its file list at 300, and a capped list hides whatever falls off the end
  if [ "$(printf '%s\n' "$INCOMING_PATHS" | grep -c .)" -ge 300 ]; then INCOMING_TRUNCATED=1; fi
fi

LOCAL_PATHS=$(git status --porcelain=v1 --no-renames 2>/dev/null | cut -c4-)
LOCAL_PROTECTED=$(printf '%s\n' "$LOCAL_PATHS" | protected_paths | paste -sd, - | sed 's/,/, /g')

# the join between incoming and local dirty: a merge writes it first, pop then refuses to restore
COLLIDING=""
if [ "$BEHIND" -gt 0 ] && [ -n "$LOCAL_PATHS" ]; then
  COLLIDING=$(comm -12 <(printf '%s\n' "$INCOMING_PATHS" | sort -u) <(printf '%s\n' "$LOCAL_PATHS" | sort -u) \
    | grep -v '^$' | paste -sd, - | sed 's/,/, /g' || true)
fi

# ==============
# OBJECT CHECK
# ==============
# the api gave the counts, but the emitted merge still needs the commits in the local object db
# a sandboxed fetch lands them and then exits 255 on .git/FETCH_HEAD, so the exit code is recorded
FETCH_RC=0
git fetch origin "$DEFAULT_BRANCH" --quiet 2>/dev/null || FETCH_RC=$?

# the merge names the tracking ref, so that ref is verified against the api rather than assumed
TRACKING_SHA=$(git rev-parse "origin/$DEFAULT_BRANCH" 2>/dev/null || true)
TRACKING="stale"
if [ "$TRACKING_SHA" = "$REMOTE_SHA" ] && git cat-file -e "$REMOTE_SHA^{commit}" 2>/dev/null; then
  TRACKING="current"; fi

NEEDS_MOVE=0
if [ "$CURRENT_BRANCH" != "$DEFAULT_BRANCH" ] || [ "$BEHIND" -gt 0 ]; then NEEDS_MOVE=1; fi

if [ "$AHEAD" -gt 0 ]; then SYNC_STATE="diverged"
elif [ -n "$COLLIDING" ]; then SYNC_STATE="colliding, the sync is yours to run"
elif [ "$INCOMING_TRUNCATED" -eq 1 ]; then SYNC_STATE="behind, but the sync is yours to run"
elif [ "$BEHIND" -gt 0 ] && [ "$TRACKING" = "stale" ]; then
  SYNC_STATE="behind, but the sync is yours to run"
elif [ -n "$INCOMING_PROTECTED" ]; then SYNC_STATE="behind, but the sync is yours to run"
elif [ -n "$LOCAL_PROTECTED" ] && [ "$DIRTY" -eq 1 ] && [ "$NEEDS_MOVE" -eq 1 ]; then
  SYNC_STATE="behind, but the sync is yours to run"
elif [ "$NEEDS_MOVE" -eq 0 ]; then SYNC_STATE="up to date"
else SYNC_STATE="behind, fast-forwards cleanly"; fi

telemetry_open gitgud:continue
telemetry_line "default branch" "$DEFAULT_BRANCH"
telemetry_line "current branch" "$CURRENT_BRANCH"
telemetry_line "repo" "$REPO_SLUG"
telemetry_line "local trunk" "${LOCAL_SHA:0:7}"
telemetry_line "origin trunk (api)" "${REMOTE_SHA:0:7}"
telemetry_line "compare status" "$CMP_STATUS"
telemetry_line "uncommitted files" "$CHANGED_FILES"
telemetry_line "trunk behind origin" "$BEHIND"
telemetry_line "trunk ahead of origin" "$AHEAD"
telemetry_line "tracking ref" "$TRACKING"
telemetry_line "fetch exit (objects only)" "$FETCH_RC"
telemetry_line "incoming list truncated" "$INCOMING_TRUNCATED"
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
  printf 'repo: %s\n' "$REPO_SLUG"
  printf 'local trunk: %s\n' "$LOCAL_SHA"
  printf 'origin trunk (api): %s\n' "$REMOTE_SHA"
  printf 'compare status: %s\n' "$CMP_STATUS"
  printf 'uncommitted files: %s\n' "$CHANGED_FILES"
  printf 'trunk behind origin: %s\n' "$BEHIND"
  printf 'trunk ahead of origin: %s\n' "$AHEAD"
  printf 'tracking ref: %s\n' "$TRACKING"
  printf 'fetch exit (objects only): %s\n' "$FETCH_RC"
  printf 'incoming list truncated: %s\n' "$INCOMING_TRUNCATED"
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
elif [ "$SYNC_STATE" = "behind, but the sync is yours to run" ]; then
  if [ "$INCOMING_TRUNCATED" -eq 1 ]; then
    handover_note "DO NOT RUN THESE — compare capped its file list at 300"
    handover_note "a capped list cannot prove the incoming set is free of protected paths"
  elif [ "$TRACKING" = "stale" ]; then
    handover_note "DO NOT RUN THESE — origin/$DEFAULT_BRANCH is not at ${REMOTE_SHA:0:7} locally"
    handover_note "the sandboxed fetch exited $FETCH_RC without leaving the objects behind"
    handover_note "run the fetch first, since the merge below reads the tracking ref"
    handover_cmd "git fetch origin $DEFAULT_BRANCH"
  else
    handover_note "DO NOT RUN THESE — the sync writes paths no sandboxed command can:"
    handover_note "incoming: ${INCOMING_PROTECTED:-none}"
    handover_note "local: ${LOCAL_PROTECTED:-none}"
  fi
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

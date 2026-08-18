#!/bin/bash
# ====================================================
# @file continue.sh - trunk sync measure and hand over
# ====================================================
# @description
# PAIR
# - sidecar for `/gitgud:continue` — measures the trunk delta, then emits the sync commands in order
# - pause work, sync the trunk, resume: the sync always ends on the trunk, never a feature branch
# SIDECAR
# - read-only: it plans the sequence and the trigger runs it, so the sidecar itself stays measuring
# - fetch is the one write it makes, and it only moves remote-tracking refs
# - measures ahead/behind after the fetch, so the handover names the real work
# - separates ahead from behind, since a behind trunk fast-forwards and never needs `/gitgud:nuke`
# - the earlier version ran the sequence itself and read a behind trunk as diverged
# TRIGGER
# - the four sync forms are narrow allows, which the trigger runs one tool call at a time
# - a diverged trunk is handed over instead, since a rebase and a merge commit both rewrite history
# @see plugins/gitgud/skills/continue/SKILL.md, plugins/gitgud/skills/nuke/SKILL.md, plugins/gitgud/shared/handover.sh, .claude/skills/validate-skills/SKILL.md

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

# fetch before measuring, or every count below describes a stale remote; its stderr is held back
# because osxkeychain cannot reach a denied keychain and says so on every sandboxed fetch, which
# is noise on a public remote and would otherwise land in the middle of the telemetry
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

# a sandboxed merge cannot write every path, and it half applies rather than refusing, so an
# incoming policy path downgrades the sync from something the trigger runs to a handover (see #127)
PROTECTED_PATHS=""
if [ "$BEHIND" -gt 0 ]; then
  PROTECTED_PATHS=$(protected_incoming "$DEFAULT_BRANCH..origin/$DEFAULT_BRANCH" \
    | paste -sd, - | sed 's/,/, /g')
fi

if [ "$AHEAD" -gt 0 ]; then SYNC_STATE="diverged"
elif [ -n "$PROTECTED_PATHS" ]; then SYNC_STATE="behind, but the sync is yours to run"
elif [ "$BEHIND" -gt 0 ]; then SYNC_STATE="behind, fast-forwards cleanly"
else SYNC_STATE="up to date"; fi

telemetry_open gitgud:continue
telemetry_line "default branch" "$DEFAULT_BRANCH"
telemetry_line "current branch" "$CURRENT_BRANCH"
telemetry_line "uncommitted files" "$CHANGED_FILES"
telemetry_line "trunk behind origin" "$BEHIND"
telemetry_line "trunk ahead of origin" "$AHEAD"
telemetry_line "sync state" "$SYNC_STATE"
telemetry_line "sandbox-denied incoming paths" "${PROTECTED_PATHS:-none}"

# the stash only earns its place when something has to move underneath it; a dirty tree with
# nothing to switch to and nothing to fast-forward would otherwise get a push/pop that is a no-op
NEEDS_MOVE=0
if [ "$CURRENT_BRANCH" != "$DEFAULT_BRANCH" ] || [ "$BEHIND" -gt 0 ]; then NEEDS_MOVE=1; fi

handover_open gitgud:continue
if [ "$AHEAD" -gt 0 ]; then
  handover_note "$DEFAULT_BRANCH has $AHEAD local commit(s) origin does not — resolve before syncing"
  handover_note "inspect them first: git log --oneline origin/$DEFAULT_BRANCH..$DEFAULT_BRANCH"
elif [ "$NEEDS_MOVE" -eq 0 ]; then
  handover_note "nothing to do — you are on $DEFAULT_BRANCH and in sync with origin"
  if [ "$DIRTY" -eq 1 ]; then
    handover_note "your $CHANGED_FILES uncommitted file(s) are untouched, which is the point"
  fi
else
  if [ -n "$PROTECTED_PATHS" ]; then
    handover_note "DO NOT RUN THESE — the sync writes paths no sandboxed command can: $PROTECTED_PATHS"
    handover_note "paste the block into your own terminal instead, in the order printed"
  else
    handover_note "the trigger runs these in order, stopping at the first non-zero exit"
  fi
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

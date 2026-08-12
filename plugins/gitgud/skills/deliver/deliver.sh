#!/bin/bash
# ====================================================
# @file deliver.sh - atomic delivery preflight sidecar
# ====================================================
# @description
# PAIR
# - sidecar for `/gitgud:deliver` — proves auth and state, then hands the prep commands over
# - the trigger drains uncommitted work in atomic `type(scope)` buckets, one pr per bucket
# - a bucket runs branch, commit, push, pr, auto-merge on green, then back to the trunk
# - the reasoning is the automation: bucketing, ordering and message drafting are what it does
# GATE
# - it plans EVERY bucket first and stops there, since a wrong bucket is free to fix before a branch
# - `--debug` plans everything the same way, but emits only the first block
# - `--finished` buckets only work that reads as finished, leaving unfinished files in the tree
# - gated: it never delivers, and every block is the user's to paste in the order given
# SIDECAR
# - read-only: switch, merge and restore are denied, so the preflight measures rather than moves
# - github auth preflights through curl + bearer, since gh cannot verify tls in the sandbox
# - github's git endpoints take only basic auth, which base64s past the proxy, so push needs a tty
# - a delivered `.claude/settings.json` strands its checkout, so the pull after needs the hatch
# @see plugins/gitgud/skills/deliver/SKILL.md, plugins/gitgud/skills/rerun/SKILL.md, plugins/gitgud/shared/handover.sh, .claude/skills/validate-skills/SKILL.md

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
require_tools curl jq
require_no_op_in_progress

# check the github token is present; inside the sandbox it holds the masked sentinel
# the proxy swaps for the real value — outside it holds the real token (curl takes both)
if [ -z "${GH_TOKEN:-}" ]; then
  echo "fatal: GH_TOKEN is not set (see README.md > Settings > Keys)" >&2; exit 1; fi

# prove the token authenticates before the delivery loop starts; bearer auth is the one
# shape the mask proxy can substitute (see plugins/operator/settings/settings.user.md > github)
AUTH_CODE=$(curl -sS --max-time 15 -o /dev/null -w '%{http_code}' \
  -H "Authorization: Bearer $GH_TOKEN" https://api.github.com/user 2>/dev/null || echo 000)
if [ "$AUTH_CODE" != "200" ]; then
  echo "fatal: github api auth failed (http $AUTH_CODE)" >&2; exit 1; fi

DEFAULT_BRANCH=$(git_default_branch)
CURRENT_BRANCH=$(git_current_branch)

if [ -z "$DEFAULT_BRANCH" ]; then
  echo "fatal: missing remote default branch" >&2; exit 1; fi
if [ -z "$CURRENT_BRANCH" ]; then
  echo "fatal: detached HEAD" >&2; exit 1; fi

# there is nothing to bucket without uncommitted work, and the loop below assumes there is
if ! git_is_dirty; then
  echo "fatal: working tree clean" >&2; exit 1; fi

FETCH_ERR=""
if ! FETCH_ERR=$(git fetch origin "$DEFAULT_BRANCH" --quiet 2>&1); then
  echo "fatal: could not fetch origin/$DEFAULT_BRANCH" >&2
  echo "$FETCH_ERR" >&2
  exit 1
fi

BEHIND=$(git rev-list --count "$DEFAULT_BRANCH..origin/$DEFAULT_BRANCH" 2>/dev/null || echo 0)
AHEAD=$(git rev-list --count "origin/$DEFAULT_BRANCH..$DEFAULT_BRANCH" 2>/dev/null || echo 0)
CHANGED_FILES=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
STAGED_FILES=$(git diff --cached --name-only 2>/dev/null | wc -l | tr -d ' ')

# a delivery touching this path strands its own checkout, so the loop needs to know up front
TOUCHES_SETTINGS=no
if git status --porcelain 2>/dev/null | grep -q '\.claude/settings\.json'; then
  TOUCHES_SETTINGS=yes
fi

telemetry_open gitgud:deliver
telemetry_line "default branch" "$DEFAULT_BRANCH"
telemetry_line "current branch" "$CURRENT_BRANCH"
telemetry_line "github auth" "ok (http $AUTH_CODE)"
telemetry_line "uncommitted files" "$CHANGED_FILES"
telemetry_line "staged files" "$STAGED_FILES"
telemetry_line "trunk behind origin" "$BEHIND"
telemetry_line "trunk ahead of origin" "$AHEAD"
telemetry_line "touches .claude/settings.json" "$TOUCHES_SETTINGS"

handover_open gitgud:deliver
if [ "$AHEAD" -gt 0 ]; then
  handover_note "$DEFAULT_BRANCH has $AHEAD commit(s) origin does not — resolve before delivering"
elif [ "$CURRENT_BRANCH" = "$DEFAULT_BRANCH" ] && [ "$BEHIND" -eq 0 ] && [ "$STAGED_FILES" -eq 0 ]; then
  handover_note "state is ready — no prep needed before the atomic loop"
else
  handover_note "run these first; the staged restore is denied, so the block stays yours"
  if [ "$CURRENT_BRANCH" != "$DEFAULT_BRANCH" ]; then
    handover_note "changes float across a switch, so your work follows you to $DEFAULT_BRANCH"
    handover_cmd "git switch $DEFAULT_BRANCH"
  fi
  if [ "$BEHIND" -gt 0 ]; then
    handover_cmd "git merge --ff-only origin/$DEFAULT_BRANCH"
  fi
  # the loop stages each bucket itself, so anything already staged would contaminate bucket one
  if [ "$STAGED_FILES" -gt 0 ]; then
    handover_cmd "git restore --staged :/"
  fi
fi
if [ "$TOUCHES_SETTINGS" = "yes" ]; then
  handover_note "this delivery touches .claude/settings.json — no sandboxed command can write it"
  handover_note "after merging, confirm and restore before pulling:"
  handover_note "git diff origin/$DEFAULT_BRANCH -- .claude/settings.json"
fi
block_close

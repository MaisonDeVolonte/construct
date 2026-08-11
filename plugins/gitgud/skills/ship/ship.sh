#!/bin/bash
# ==============================================
# @file ship.sh - release preflight and handover
# ==============================================
# @description
# PAIR
# - sidecar for `/gitgud:ship` — verifies every release precondition, then hands the sequence over
# - it aborts on any failed preflight: dirty tree, detached head, unsynced trunk, no production
# SIDECAR
# - read-only: the bump, both pushes and the promotion merge are all denied as tool calls
# - computes the next version from `package.json` rather than running `npm version` to learn it
# - auth preflights through curl + bearer, since gh cannot verify tls in the sandbox
# HANDOVER
# - `--minor`/`--major` (default minor) only decides the version the handover names
# - it bumps, pushes `main` with tags, fast-forwards `production`, pushes, then calls the release
# - `deploy.yml` listens for that `production` push, so the push is what actually ships
# - the release api call comes last, since the tag has to reach origin before it resolves
# @see plugins/gitgud/skills/ship/SKILL.md, plugins/gitgud/shared/handover.sh, .github/workflows/deploy.yml, .claude/skills/skills/SKILL.md

set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)
SHARED=$(cd "$HERE/../../shared" 2>/dev/null && pwd || true)
if [ ! -f "$SHARED/handover.sh" ]; then
  echo "fatal: no plugins/gitgud/shared/handover.sh reachable from this sidecar" >&2; exit 1; fi
# shellcheck source=../../shared/handover.sh
. "$SHARED/handover.sh"

FLAG=${1:-}
if [ "$FLAG" = "--major" ]; then TYPE="major"
elif [ "$FLAG" = "--minor" ] || [ -z "$FLAG" ]; then TYPE="minor"
else echo "fatal: release flag must be '--minor' or '--major'" >&2; exit 1; fi

require_repo
require_tools curl jq
require_no_op_in_progress

if [ -z "${GH_TOKEN:-}" ]; then
  echo "fatal: GH_TOKEN is not set (see README.md > Settings > Keys)" >&2; exit 1; fi

ROOT=$(git rev-parse --show-toplevel)
if [ ! -f "$ROOT/package.json" ]; then
  echo "fatal: no package.json to version" >&2; exit 1; fi

# owner/repo parsed from the origin url in both its https and ssh shapes
REMOTE_URL=$(git remote get-url origin 2>/dev/null || echo "")
if ! echo "$REMOTE_URL" | grep -q 'github\.com'; then
  echo "fatal: origin is not a github remote" >&2; exit 1; fi
REPO_SLUG=$(echo "$REMOTE_URL" | sed -e 's#^.*github\.com[:/]##' -e 's#\.git$##')

# prove the token authenticates before handing a release sequence to anyone
AUTH_CODE=$(curl -sS --max-time 15 -o /dev/null -w '%{http_code}' \
  -H "Authorization: Bearer $GH_TOKEN" https://api.github.com/user 2>/dev/null || echo 000)
if [ "$AUTH_CODE" != "200" ]; then
  echo "fatal: github api auth failed (http $AUTH_CODE)" >&2; exit 1; fi

DEFAULT_BRANCH=$(git_default_branch)
CURRENT_BRANCH=$(git_current_branch)
PRODUCTION_BRANCH="production"

if [ -z "$CURRENT_BRANCH" ]; then
  echo "fatal: detached HEAD" >&2; exit 1; fi
if [ "$CURRENT_BRANCH" != "$DEFAULT_BRANCH" ]; then
  echo "fatal: must be on default branch ($DEFAULT_BRANCH) to release" >&2; exit 1; fi
if git_is_dirty; then
  echo "fatal: working tree has uncommitted changes; run /gitgud:deliver first" >&2; exit 1; fi

if ! git show-ref --verify --quiet "refs/heads/$PRODUCTION_BRANCH" \
  && ! git ls-remote --exit-code --heads origin "$PRODUCTION_BRANCH" >/dev/null 2>&1; then
  echo "fatal: production branch '$PRODUCTION_BRANCH' does not exist locally or on remote" >&2; exit 1; fi

FETCH_ERR=""
if ! FETCH_ERR=$(git fetch origin "$DEFAULT_BRANCH" --quiet 2>&1); then
  echo "fatal: could not fetch origin/$DEFAULT_BRANCH" >&2
  echo "$FETCH_ERR" >&2
  exit 1
fi

BEHIND=$(git rev-list --count "$DEFAULT_BRANCH..origin/$DEFAULT_BRANCH" 2>/dev/null || echo 0)
AHEAD=$(git rev-list --count "origin/$DEFAULT_BRANCH..$DEFAULT_BRANCH" 2>/dev/null || echo 0)
if [ "$BEHIND" -ne 0 ] || [ "$AHEAD" -ne 0 ]; then
  echo "fatal: $DEFAULT_BRANCH is out of sync with origin ($AHEAD ahead, $BEHIND behind)" >&2; exit 1; fi

# the next version is computed rather than applied, since `npm version` commits and tags as it goes
CURRENT_VERSION=$(jq -r '.version // empty' "$ROOT/package.json")
if [ -z "$CURRENT_VERSION" ]; then
  echo "fatal: package.json has no version field" >&2; exit 1; fi
MAJOR=${CURRENT_VERSION%%.*}
REST=${CURRENT_VERSION#*.}
MINOR=${REST%%.*}
if [ "$TYPE" = "major" ]; then NEXT_VERSION="v$((MAJOR + 1)).0.0"
else NEXT_VERSION="v$MAJOR.$((MINOR + 1)).0"; fi

PROMOTE_COUNT=$(git rev-list --count "origin/$PRODUCTION_BRANCH..origin/$DEFAULT_BRANCH" 2>/dev/null || echo 0)

telemetry_open gitgud:ship
telemetry_line "repo" "$REPO_SLUG"
telemetry_line "github auth" "ok (http $AUTH_CODE)"
telemetry_line "default branch" "$DEFAULT_BRANCH"
telemetry_line "production branch" "$PRODUCTION_BRANCH"
telemetry_line "release type" "$TYPE"
telemetry_line "current version" "$CURRENT_VERSION"
telemetry_line "next version" "$NEXT_VERSION"
telemetry_line "commits promoting to production" "$PROMOTE_COUNT"

handover_open gitgud:ship
handover_note "run these in order; the bump, both pushes and the merge are denied as tool calls"
handover_cmd "npm version $TYPE"
handover_cmd "git push origin $DEFAULT_BRANCH --follow-tags"
handover_cmd "git switch $PRODUCTION_BRANCH"
handover_cmd "git merge --ff-only $DEFAULT_BRANCH"
handover_cmd "git push origin $PRODUCTION_BRANCH"
handover_cmd "git switch $DEFAULT_BRANCH"
handover_note "then publish the release, once the tag is on origin"
handover_cmd "curl -sS -X POST -H \"Authorization: Bearer \$GH_TOKEN\" \\
  -H 'Accept: application/vnd.github+json' \\
  https://api.github.com/repos/$REPO_SLUG/releases \\
  -d '{\"tag_name\":\"$NEXT_VERSION\",\"name\":\"Release $NEXT_VERSION\",\"generate_release_notes\":true}'"
block_close

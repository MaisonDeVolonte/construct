#!/bin/bash
# ==============================================
# @file ship.sh - release preflight and handover
# ==============================================
# @description
# PAIR
# - sidecar for `/gitgud:ship` — verifies every release precondition, then hands the sequence over
# - it aborts on any failed preflight: dirty tree, detached head, unsynced trunk, no production
# - readme drift and an unindexed skill abort it too, since both describe a whole clean tree
# - a pull request only ever carries part of one, which is why ci gates neither of them
# - both checks are maintainer tooling, so an install without them skips rather than fails
# SIDECAR
# - read-only: the bump, both pushes and the promotion merge are all denied as tool calls
# - computes the next version from the manifest rather than running `npm version` to learn it
# - `package.json` is the version source, and `.claude-plugin/marketplace.json` is the fallback
# - auth preflights through curl + bearer, since gh cannot verify tls in the sandbox
# HANDOVER
# - `--minor`/`--major` (default minor) only decides the version the handover names
# - it bumps, lands that bump on the trunk, tags it, promotes, then calls the release
# - a trunk that requires a pull request gets the branch and pr steps instead of a direct push
# - reading that rule beats assuming: a rejected push leaves the tag on a commit the trunk never has
# - nothing deploys on the promotion push; users pull, so the promotion IS the release
# - the release api call comes last, since the tag has to reach origin before it resolves
# @see plugins/gitgud/skills/ship/SKILL.md, plugins/gitgud/shared/handover.sh, .claude/skills/push-release/push-release.sh, .claude/skills/validate-skills/SKILL.md, .claude/skills/export-readme/export-readme.sh

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

FLAG=${1:-}
if [ "$FLAG" = "--major" ]; then TYPE="major"
elif [ "$FLAG" = "--minor" ] || [ -z "$FLAG" ]; then TYPE="minor"
else echo "fatal: release flag must be '--minor' or '--major'" >&2; exit 1; fi

require_repo
require_tools curl jq
require_no_op_in_progress

if [ -z "${GH_TOKEN_OPERATOR:-}" ]; then
  echo "fatal: GH_TOKEN_OPERATOR is not set (see README.md > Settings > Keys)" >&2; exit 1; fi

ROOT=$(git rev-parse --show-toplevel)

# a node project versions package.json; a claude code marketplace versions its manifest, and both
# keep the number in a top-level `version` field, so one reader covers the two shapes
VERSION_FILE=""
for candidate in package.json .claude-plugin/marketplace.json; do
  if [ -f "$ROOT/$candidate" ]; then VERSION_FILE="$candidate"; break; fi
done
if [ -z "$VERSION_FILE" ]; then
  echo "fatal: no package.json or .claude-plugin/marketplace.json to version" >&2; exit 1; fi

# the repo's own bump tool owns every file the version is repeated in, which a single sed cannot
BUMP_TOOL=".claude/skills/push-release/push-release.sh"
if [ -f "$ROOT/$BUMP_TOOL" ]; then BUMP_CMD="bash $BUMP_TOOL --$TYPE"
elif [ "$VERSION_FILE" = package.json ]; then BUMP_CMD="npm version $TYPE"
else
  echo "fatal: no bump tool for $VERSION_FILE; add $BUMP_TOOL or a package.json" >&2; exit 1; fi

# owner/repo parsed from the origin url in both its https and ssh shapes
REMOTE_URL=$(git remote get-url origin 2>/dev/null || echo "")
if ! echo "$REMOTE_URL" | grep -q 'github\.com'; then
  echo "fatal: origin is not a github remote" >&2; exit 1; fi
REPO_SLUG=$(echo "$REMOTE_URL" | sed -e 's#^.*github\.com[:/]##' -e 's#\.git$##')

# prove the token authenticates before handing a release sequence to anyone
AUTH_CODE=$(curl -sS --max-time 15 -o /dev/null -w '%{http_code}' \
  -H "Authorization: Bearer $GH_TOKEN_OPERATOR" https://api.github.com/user 2>/dev/null || echo 000)
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

# the whole-tree docs invariants: the readme copies ship inside one install directory, and the
# readme index is what makes a skill discoverable; the tree is clean by the check above
EXPORTER="$ROOT/.claude/skills/export-readme/export-readme.sh"
if [ -f "$EXPORTER" ] && ! DOCS=$(bash "$EXPORTER" --check 2>&1); then
  echo "fatal: readme drift; run $EXPORTER, then commit what it wrote" >&2
  printf '%s\n' "$DOCS" >&2
  exit 1
fi
VALIDATOR="$ROOT/.claude/skills/validate-skills/validate-skills.sh"
if [ -f "$VALIDATOR" ] && ! DOCS=$(bash "$VALIDATOR" --strict 2>&1); then
  echo "fatal: a skill pair fails --strict; every warning gates the release" >&2
  printf '%s\n' "$DOCS" >&2
  exit 1
fi

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

# the next version is computed rather than applied, since a bump tool commits and tags as it goes
CURRENT_VERSION=$(jq -r '.version // empty' "$ROOT/$VERSION_FILE")
if [ -z "$CURRENT_VERSION" ]; then
  echo "fatal: $VERSION_FILE has no version field" >&2; exit 1; fi
MAJOR=${CURRENT_VERSION%%.*}
REST=${CURRENT_VERSION#*.}
MINOR=${REST%%.*}
if [ "$TYPE" = "major" ]; then NEXT_VERSION="v$((MAJOR + 1)).0.0"
else NEXT_VERSION="v$MAJOR.$((MINOR + 1)).0"; fi

PROMOTE_COUNT=$(git rev-list --count "origin/$PRODUCTION_BRANCH..origin/$DEFAULT_BRANCH" 2>/dev/null || echo 0)

# a trunk rule that requires a pull request rejects the bump push, and the tag is already made by
# then, so the release ends up on a commit the trunk never contains; reading the rule avoids that
TRUNK_RULES=$(curl -sS --max-time 15 -H "Authorization: Bearer $GH_TOKEN_OPERATOR" \
  "https://api.github.com/repos/$REPO_SLUG/rules/branches/$DEFAULT_BRANCH" 2>/dev/null || echo '[]')
TRUNK_GATE=direct
if printf '%s' "$TRUNK_RULES" | jq -e 'any(.[]?; .type == "pull_request")' >/dev/null 2>&1; then
  TRUNK_GATE="pull request required"; fi

telemetry_open gitgud:ship
telemetry_line "repo" "$REPO_SLUG"
telemetry_line "github auth" "ok (http $AUTH_CODE)"
telemetry_line "default branch" "$DEFAULT_BRANCH"
telemetry_line "production branch" "$PRODUCTION_BRANCH"
telemetry_line "release type" "$TYPE"
telemetry_line "current version" "$CURRENT_VERSION"
telemetry_line "next version" "$NEXT_VERSION"
telemetry_line "commits promoting to production" "$PROMOTE_COUNT"
telemetry_line "version source" "$VERSION_FILE"
telemetry_line "trunk gate" "$TRUNK_GATE"

handover_open gitgud:ship
handover_note "run these in order; the bump, both pushes and the merge are denied as tool calls"
handover_cmd "$BUMP_CMD"
if [ "$TRUNK_GATE" = direct ]; then
  handover_cmd "git commit -am \"release: ${NEXT_VERSION#v}\""
  handover_cmd "git tag -a $NEXT_VERSION -m \"Release $NEXT_VERSION\""
  handover_cmd "git push origin $DEFAULT_BRANCH --follow-tags"
else
  handover_note "the trunk takes no direct push, so the bump lands as its own pull request first"
  handover_cmd "git switch -c release/${NEXT_VERSION#v} $DEFAULT_BRANCH"
  handover_cmd "git commit -am \"release: ${NEXT_VERSION#v}\""
  handover_cmd "git push -u origin release/${NEXT_VERSION#v}"
  handover_cmd "gh pr create --base $DEFAULT_BRANCH --fill"
  handover_cmd "gh pr merge --auto --rebase"
  handover_note "then, ONCE that pull request shows merged, tag the sha the trunk actually kept"
  handover_cmd "git switch $DEFAULT_BRANCH"
  handover_cmd "git pull --ff-only origin $DEFAULT_BRANCH"
  handover_cmd "git branch -D release/${NEXT_VERSION#v}"
  handover_cmd "git tag -a $NEXT_VERSION -m \"Release $NEXT_VERSION\""
  handover_cmd "git push origin $NEXT_VERSION"
fi
handover_cmd "git switch $PRODUCTION_BRANCH"
handover_cmd "git merge --ff-only $DEFAULT_BRANCH"
handover_cmd "git push origin $PRODUCTION_BRANCH"
handover_cmd "git switch $DEFAULT_BRANCH"
handover_note "then publish the release, once the tag is on origin"
handover_cmd "curl -sS -X POST -H \"Authorization: Bearer \$GH_TOKEN_OPERATOR\" \\
  -H 'Accept: application/vnd.github+json' \\
  https://api.github.com/repos/$REPO_SLUG/releases \\
  -d '{\"tag_name\":\"$NEXT_VERSION\",\"name\":\"Release $NEXT_VERSION\",\"generate_release_notes\":true}'"
block_close

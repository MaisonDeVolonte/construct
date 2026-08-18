#!/bin/bash
# ==========================================================================
# @file push-release.sh - release preflight, version write, and the handover
# ==========================================================================
# @description
# SCHEME
# - the version is `MAJOR.MINOR.PATCH`, stored rather than derived, and bumped by a person
# - `main` is the integration trunk and reaches no user, since the marketplace ref is `production`
# - a merge to `production` is the release, and the bumped version is what fires `/plugin update`
# - PATCH is the default, because most releases here are fixes to skills that already shipped
# SOURCE
# - the three `plugins/*/.claude-plugin/plugin.json` files carry it, and all three must agree
# - `.claude-plugin/marketplace.json` carries its own top-level version, moved by the same run
# - no marketplace entry carries one: `plugin.json` outranks it, so a drifted pair reads silently
# - no CHANGELOG is written; the github release generates its notes from the commits
# RUN
# - `--check` is the read-only gate ci runs: the four files agree and every value parses as semver
# - `--patch` (the default), `--minor` and `--major` each preflight, write the four, then hand over
# SIDECAR
# - read-only apart from the four version lines: it never commits, never merges, and never pushes
# - the sequence is emitted into the handover block, including the release api call
# - the write is a `sed` on the version line, never a `jq` render, so the rest of each file survives
# ARTIFACT
# - `.construct/maintainer/push-release/YYYY-MM-DD.md`, one file per day, appended by the agent
# - reported, never created: this names the path and the count, and the doc says what to write
# - `--check` returns before the telemetry, so that mode names no artifact at all
# @see .claude/skills/push-release/SKILL.md, .claude-plugin/marketplace.json, .github/workflows/ci.yml, plugins/gitgud/skills/ship/SKILL.md, .construct/maintainer/push-release/
set -euo pipefail

# the doc is read only after this has already run, so help is refused here or not at all; the doc's
# own '## Help' section owns the output, which is why this prints a marker rather than a usage text
case " $* " in *" --help "*|*" -h "*) echo "help: requested"; exit 0;; esac

# the smoke case proves this file parses and its guards return; /test-skills reads the sources,
# the @see paths and the tool guards statically, so nothing here runs a step of the skill
case " $* " in *" --test "*) echo "test: ok"; exit 0;; esac

# the day's artifact is named here and written by the agent, the same split every other skill in
# this repo makes; the `--check` path returns before the telemetry, so it names none
ARTIFACTS=".construct/maintainer/push-release"

# 1. global constants
MANIFESTS="plugins/*/.claude-plugin/plugin.json"
MARKETPLACE=".claude-plugin/marketplace.json"
PRODUCTION_BRANCH="production"
SEMVER='^[0-9]+\.[0-9]+\.[0-9]+$'

# 2. hoisted state
KIND="patch"
CHECK=0

for arg in "$@"; do
  case "$arg" in
    --check) CHECK=1 ;;
    --patch) KIND="patch" ;;
    --minor) KIND="minor" ;;
    --major) KIND="major" ;;
    *) echo "fatal: unknown argument '$arg'" >&2; exit 1 ;;
  esac
done

# 3. defined helpers

# every version line in this repo has the same shape, so one reader serves all four files
read_version() {
  sed -n 's/^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$1" | head -1
}

# a `jq` render would reflow every hand-formatted object in the marketplace, so the write is a sed
write_version() {
  local file=$1 value=$2 tmp="$1.tmp"
  sed 's/^\([[:space:]]*"version"[[:space:]]*:[[:space:]]*\)"[^"]*"/\1"'"$value"'"/' \
    "$file" > "$tmp" && mv "$tmp" "$file"
}

# the trunk is whatever origin points HEAD at, so a fork with a `master` default still releases
default_branch() {
  local ref
  ref=$(git symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null || echo "")
  if [ -n "$ref" ]; then basename "$ref"; return 0; fi
  if git show-ref --verify --quiet refs/heads/main; then echo main; return 0; fi
  echo master
}

die() { echo "fatal: $1" >&2; exit 1; }

# 4. main logic & execution

command -v git >/dev/null 2>&1 || die "git is not on PATH"
git rev-parse --show-toplevel >/dev/null 2>&1 || die "not a git repo"
ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"

# ==============
# READ
# ==============
# the four files are one version said four times, so disagreement is the first thing measured
VERSIONS=""
FILES=""
for m in $MANIFESTS "$MARKETPLACE"; do
  [ -f "$m" ] || die "$m is missing, so there is no version to read"
  have=$(read_version "$m")
  [ -n "$have" ] || die "$m carries no version field"
  echo "$have" | grep -qE "$SEMVER" || die "$m reads '$have', which is not MAJOR.MINOR.PATCH"
  VERSIONS="$VERSIONS$have\n"
  FILES="$FILES $m"
done

AGREED=$(printf '%b' "$VERSIONS" | sort -u | grep -c . || true)
CURRENT=$(printf '%b' "$VERSIONS" | head -1)
COUNT=$(printf '%b' "$VERSIONS" | grep -c . || true)

# ==============
# CHECK
# ==============
# ci runs this and nothing else: it is pure, it reaches no network, and it writes nothing
if [ "$CHECK" = "1" ]; then
  if [ "$AGREED" != "1" ]; then
    echo "the version files disagree; every one of them ships in the same install:" >&2
    for m in $FILES; do printf '  %-46s %s\n' "$m" "$(read_version "$m")" >&2; done
    exit 1
  fi
  echo "all $COUNT version files read $CURRENT"
  exit 0
fi

[ "$AGREED" = "1" ] || die "the version files disagree; run --check to see which"

# ==============
# PREFLIGHT
# ==============
# every one of these aborts, because a half-run release leaves the trunk and production diverged
command -v jq >/dev/null 2>&1 || die "jq is not on PATH"
command -v curl >/dev/null 2>&1 || die "curl is not on PATH"
[ -n "${GH_TOKEN_OPERATOR:-}" ] || die "GH_TOKEN_OPERATOR is not set (see README.md > Settings > Keys)"

REMOTE_URL=$(git remote get-url origin 2>/dev/null || echo "")
echo "$REMOTE_URL" | grep -q 'github\.com' || die "origin is not a github remote"
REPO_SLUG=$(echo "$REMOTE_URL" | sed -e 's#^.*github\.com[:/]##' -e 's#\.git$##')

# prove the token authenticates before handing a release sequence to anyone
AUTH_CODE=$(curl -sS --max-time 15 -o /dev/null -w '%{http_code}' \
  -H "Authorization: Bearer $GH_TOKEN_OPERATOR" https://api.github.com/user 2>/dev/null || echo 000)
[ "$AUTH_CODE" = "200" ] || die "github api auth failed (http $AUTH_CODE)"

TRUNK=$(default_branch)
BRANCH=$(git rev-parse --abbrev-ref HEAD)
[ "$BRANCH" != "HEAD" ] || die "detached HEAD"
[ "$BRANCH" = "$TRUNK" ] || die "must be on the trunk ($TRUNK) to release, not $BRANCH"
[ -z "$(git status --porcelain)" ] || die "working tree has uncommitted changes; run /gitgud:deliver first"

git ls-remote --exit-code --heads origin "$PRODUCTION_BRANCH" >/dev/null 2>&1 \
  || die "no origin/$PRODUCTION_BRANCH; create it from $TRUNK before the first release"

git fetch origin "$TRUNK" "$PRODUCTION_BRANCH" --quiet 2>/dev/null \
  || die "could not fetch origin/$TRUNK and origin/$PRODUCTION_BRANCH"

BEHIND=$(git rev-list --count "$TRUNK..origin/$TRUNK" 2>/dev/null || echo 0)
AHEAD=$(git rev-list --count "origin/$TRUNK..$TRUNK" 2>/dev/null || echo 0)
[ "$BEHIND" -eq 0 ] && [ "$AHEAD" -eq 0 ] \
  || die "$TRUNK is out of sync with origin ($AHEAD ahead, $BEHIND behind)"

# production must stay a fast-forward of the trunk, since a commit landing there directly ends
# every later `merge --ff-only` and the release path dies with it
git merge-base --is-ancestor "origin/$PRODUCTION_BRANCH" "origin/$TRUNK" 2>/dev/null \
  || die "origin/$PRODUCTION_BRANCH has diverged from $TRUNK, so it can no longer fast-forward"

PROMOTE_COUNT=$(git rev-list --count "origin/$PRODUCTION_BRANCH..origin/$TRUNK" 2>/dev/null || echo 0)
[ "$PROMOTE_COUNT" -gt 0 ] || die "nothing to release: $PRODUCTION_BRANCH already matches $TRUNK"

# ==============
# NEXT
# ==============
MAJOR=${CURRENT%%.*}
REST=${CURRENT#*.}
MINOR=${REST%%.*}
PATCH=${CURRENT##*.}
case "$KIND" in
  patch) NEXT="$MAJOR.$MINOR.$((PATCH + 1))" ;;
  minor) NEXT="$MAJOR.$((MINOR + 1)).0" ;;
  major) NEXT="$((MAJOR + 1)).0.0" ;;
esac

# ==============
# WRITE
# ==============
WROTE=0
for m in $FILES; do
  write_version "$m" "$NEXT"
  WROTE=$((WROTE + 1))
done

# ==============
# TELEMETRY
# ==============
# one file per day: the count is read off the headings already in it, so the number the agent
# writes survives a run that reported nothing. `grep -c` exits 1 on no match, hence the `|| true`
TODAYS_AUDIT="$ARTIFACTS/$(date +%Y-%m-%d).md"
if [ -f "$TODAYS_AUDIT" ];
then AUDIT_COUNT=$(grep -c '^## Release Audit #' "$TODAYS_AUDIT" || true)
else AUDIT_COUNT=0; fi
AUDIT_COUNT=${AUDIT_COUNT:-0}

cat <<EOF

=== /push-release telemetry ===
repo: $REPO_SLUG
github auth: ok (http $AUTH_CODE)
trunk: $TRUNK
production branch: $PRODUCTION_BRANCH
release type: $KIND
current version: $CURRENT
next version: $NEXT
version files written: $WROTE
commits promoting to production: $PROMOTE_COUNT
audit_file: $TODAYS_AUDIT
audit_count: $AUDIT_COUNT
next_audit: $((AUDIT_COUNT + 1))
timestamp: $(date '+%Y-%m-%d %H:%M')
EOF

printf '\n%-46s %-10s %s\n' 'FILE' 'WAS' 'NOW'
for m in $FILES; do printf '%-46s %-10s %s\n' "$m" "$CURRENT" "$(read_version "$m")"; done

# a trunk rule requiring a pull request rejects step 4 below, and the tag exists by then, so the
# release ends up on a sha the trunk never keeps; the rule is read rather than assumed
TRUNK_GATE=direct
if curl -sS --max-time 15 -H "Authorization: Bearer $GH_TOKEN_OPERATOR" \
  "https://api.github.com/repos/$REPO_SLUG/rules/branches/$TRUNK" 2>/dev/null \
  | jq -e 'any(.[]?; .type == "pull_request")' >/dev/null 2>&1; then
  TRUNK_GATE="pull request required"; fi
printf '\ntrunk gate: %s\n' "$TRUNK_GATE"

# ==============
# HANDOVER
# ==============
# every mutating verb below is denied as a tool call by the floor this repo ships
# so the whole sequence is emitted for a person to read once and paste
# the steps are built into a function rather than printed straight out, so the agent copying them
# into the artifact quotes the one text a person pasted, never a second heredoc that could drift
handover_steps() {
if [ "$TRUNK_GATE" = direct ]; then
cat <<EOF
# 1. stage the four version files this run wrote, and nothing else
git add $MANIFESTS $MARKETPLACE

# 2. commit them alone, so the commit says only what it did
git commit -m "release: $NEXT"

# 3. tag the release on the trunk, before anything is pushed
git tag -a v$NEXT -m "Release v$NEXT"

# 4. push the trunk with its tag
git push origin $TRUNK --follow-tags
EOF
else
cat <<EOF
# 1. branch FIRST: the trunk requires a pull request, so a commit on it strands the local trunk
git switch -c release/$NEXT $TRUNK

# 2. stage and commit the four version files this run wrote, and nothing else
git add $MANIFESTS $MARKETPLACE
git commit -m "release: $NEXT"

# 3. open the pull request and let the required check merge it
git push -u origin release/$NEXT
gh pr create --base $TRUNK --fill
gh pr merge --auto --rebase

# 4. ONCE it shows merged, tag the sha the rebase actually left on the trunk
git switch $TRUNK
git pull --ff-only origin $TRUNK
git branch -D release/$NEXT
git tag -a v$NEXT -m "Release v$NEXT"
git push origin v$NEXT
EOF
fi

cat <<EOF

# 5. promote, which is the push that actually releases to every install
git switch $PRODUCTION_BRANCH
git merge --ff-only $TRUNK
git push origin $PRODUCTION_BRANCH
git switch $TRUNK

# 6. publish the release, once the tag is on origin; the notes generate from the commits
curl -sS -X POST -H "Authorization: Bearer \$GH_TOKEN_OPERATOR" \\
  -H 'Accept: application/vnd.github+json' \\
  https://api.github.com/repos/$REPO_SLUG/releases \\
  -d '{"tag_name":"v$NEXT","name":"Release v$NEXT","generate_release_notes":true}'
EOF
}

printf '\n=== /push-release handover ===\n%s\n=====================\n' "$(handover_steps)"

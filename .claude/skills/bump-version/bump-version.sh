#!/bin/bash
# ======================================================================
# @file bump-version.sh - derive the repo version and hand the bump over
# ======================================================================
# @description
# SCHEME
# - the version is `vMAJOR.MINOR.PATCH`, and only the MINOR tags exist as real refs
# - MINOR is the plugin count, so it moves on the commit that adds a plugin tree and never else
# - PATCH is `git rev-list --count <minor tag>..HEAD`, derived on every run and never tagged
# - a patch tag would become the newest tag and reset that count, so the match glob excludes them
# SOURCE
# - the anchor is the newest tag matching `v[0-9]*.[0-9]*.0` reachable from HEAD
# - the three `plugins/*/.claude-plugin/plugin.json` files carry the ERA, `MAJOR.MINOR.0`
# - a stored patch would go stale on the commit that stored it, so the patch is never written
# RUN
# - a bare run reports the anchor, the derived version and the manifest drift, and writes nothing
# - `--minor` opens the next plugin era and `--major` the next major; both write and both tag
# - `--repair` restates the current era when a manifest drifted, and carries no tag
# SIDECAR
# - read-only by default: it never commits, never tags, and never pushes
# - the commit, the tag and the push are emitted into the handover block instead
# - the tag is retro-dated through GIT_COMMITTER_DATE so `log --decorate` reads chronologically
# @see .claude/skills/bump-version/SKILL.md, .claude-plugin/marketplace.json, plugins/gitgud/skills/ship/ship.sh
set -euo pipefail

# the doc is read only after this has already run, so help is refused here or not at all; the doc's
# own '## Help' section owns the output, which is why this prints a marker rather than a usage text
case " $* " in *" --help "*|*" -h "*) echo "help: requested"; exit 0;; esac

REPAIR=0
KIND="report"
for arg in "$@"; do
  case "$arg" in
    --repair) REPAIR=1 ;;
    --minor) KIND="minor" ;;
    --major) KIND="major" ;;
    *) echo "fatal: unknown argument '$arg'" >&2; exit 1 ;;
  esac
done

# ==============
# preflights
# ==============
command -v git >/dev/null 2>&1 || { echo "fatal: git is not on PATH" >&2; exit 1; }
git rev-parse --show-toplevel >/dev/null 2>&1 || { echo "fatal: not a git repo" >&2; exit 1; }
ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"

MATCH='v[0-9]*.[0-9]*.0'
ANCHOR=$(git describe --tags --abbrev=0 --match "$MATCH" 2>/dev/null || echo "")
if [ -z "$ANCHOR" ]; then
  echo "fatal: no minor tag matching $MATCH is reachable from HEAD" >&2
  echo "hint: the anchor tags are cut once, retroactively; see the spec" >&2
  exit 1
fi

MAJOR=${ANCHOR#v}; MAJOR=${MAJOR%%.*}
REST=${ANCHOR#v"$MAJOR".}
MINOR=${REST%%.*}
PATCH=$(git rev-list --count "$ANCHOR"..HEAD)
CURRENT="v$MAJOR.$MINOR.$PATCH"

# the manifest carries the era and never the patch, so a report targets the era it is already in
case "$KIND" in
  report) ERA="v$MAJOR.$MINOR.0" ;;
  minor) ERA="v$MAJOR.$((MINOR + 1)).0" ;;
  major) ERA="v$((MAJOR + 1)).0.0" ;;
esac
ERA_BARE=${ERA#v}

DIRTY=$(git status --porcelain | wc -l | tr -d ' ')
BRANCH=$(git rev-parse --abbrev-ref HEAD)
PLUGINS=$(ls -d plugins/*/.claude-plugin/plugin.json 2>/dev/null | wc -l | tr -d ' ')

# ==============
# manifests
# ==============
# repo-local scratch: the sandbox denies writes outside cwd, and macos mktemp ignores TMPDIR
TMPROOT="$ROOT/tmp"
mkdir -p "$TMPROOT"
SCRATCH=$(mktemp -d "$TMPROOT/version.XXXXXX")
trap 'rm -rf "$SCRATCH"' EXIT

DRIFT=0
ROWS="$SCRATCH/rows"
for m in plugins/*/.claude-plugin/plugin.json; do
  [ -f "$m" ] || continue
  have=$(sed -n 's/^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$m" | head -1)
  [ -n "$have" ] || have="none"
  state="ok"
  if [ "$have" != "$ERA_BARE" ]; then state="stale"; DRIFT=$((DRIFT + 1)); fi
  printf '%s|%s|%s|%s\n' "$(printf '%s' "$m" | cut -d/ -f2)" "$have" "$ERA_BARE" "$state" >> "$ROWS"
done

# the minor is the plugin count, so a mismatch means a tree landed without its era
COUNT_OK="ok"
if [ "$KIND" = "report" ] && [ "$PLUGINS" != "$MINOR" ]; then COUNT_OK="mismatch"; fi

# ==============
# write
# ==============
# a bare run writes nothing at all, so the everyday invocation cannot dirty the tree
WROTE=0
if [ "$KIND" != "report" ] || [ "$REPAIR" = "1" ]; then
  if [ "$DRIFT" = "0" ]; then
    echo "nothing to write: every manifest already reads $ERA_BARE"
  else
    for m in plugins/*/.claude-plugin/plugin.json; do
      [ -f "$m" ] || continue
      tmp="$m.tmp"
      sed 's/^\([[:space:]]*"version"[[:space:]]*:[[:space:]]*\)"[^"]*"/\1"'"$ERA_BARE"'"/' \
        "$m" > "$tmp" && mv "$tmp" "$m"
      WROTE=$((WROTE + 1))
      echo "wrote $m ($ERA_BARE)"
    done
  fi
fi

# ==============
# telemetry
# ==============
cat <<EOF

=== /bump-version telemetry ===
anchor: $ANCHOR
version: $CURRENT (derived, stored nowhere)
manifest era: $ERA ($KIND)
commits since anchor: $PATCH
plugins on disk: $PLUGINS
minor vs plugin count: $COUNT_OK
manifests drifted: $DRIFT
manifests written: $WROTE
branch: $BRANCH
uncommitted files: $DIRTY
EOF

printf '\n%-14s %-10s %-10s %s\n' 'PLUGIN' 'MANIFEST' 'TARGET' 'STATE'
awk -F'|' '{ printf "%-14s %-10s %-10s %s\n", $1, $2, $3, $4 }' "$ROWS"

# ==============
# handover
# ==============
if [ "$WROTE" = "0" ]; then
  cat <<EOF

=== /bump-version handover ===
# nothing was written, so there is nothing to commit
# the version is $CURRENT and it lives in the tags, not in a file
=====================
EOF
  exit 0
fi

TAGLINE="# no tag: a repair restates the era it is already in"
if [ "$KIND" != "report" ]; then
  TAGLINE="git tag -a $ERA -m '<what this era opens>'"
fi

cat <<EOF

=== /bump-version handover ===
# 1. stage the manifests this run wrote, and nothing else
git add plugins/*/.claude-plugin/plugin.json

# 2. commit them alone, so the commit says only what it did
git commit -m "update(version): set the manifest era to $ERA_BARE"

# 3. tag only when the era changes; a repair carries no tag
$TAGLINE

# 4. push the branch, then the tags, once you have read the two above
git push origin $BRANCH
git push origin --tags
=====================
EOF

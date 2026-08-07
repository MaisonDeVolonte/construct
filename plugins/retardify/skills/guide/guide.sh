#!/bin/bash
# ==============================================
# @file guide.sh - build guide preflight sidecar
# ==============================================
# @description
# PAIR
# - sidecar for `/retardify:guide` — computes where the guide lands, and says if one already covers it
# - it measures only; the doc writes the file, since prose is the deliverable and not telemetry
# ARTIFACT
# - `docs/guides/<slug>.md` in kebab-case, the shape `doc-guides` documents and validates
# - undated on purpose: a guide describes what is true now, so a second one replaces the first
# - a collision is reported rather than resolved, since replacing a guide is the user's call
# RUN
# - the feature arrives as arguments, and an empty one is fatal rather than a file with no name
# - `mkdir -p` on the artifact directory is the one write it makes, and it is idempotent
# @see AGENTS.md, plugins/retardify/skills/guide/SKILL.md, plugins/retardify/skills/guide/SKILL.md, plugins/retardify/skills/guide/doc-guides.sh, docs/guides/

set -euo pipefail

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "fatal: not a git repository" >&2; exit 1; fi
cd "$(git rev-parse --show-toplevel)"

ARTIFACTS="docs/guides"
TEMPLATE="plugins/retardify/skills/guide/SKILL.md"
VALIDATOR="plugins/retardify/skills/guide/doc-guides.sh"

FEATURE="$*"
if [ -z "$FEATURE" ]; then
  echo "fatal: /write-guide needs a feature, as in: /write-guide the settings audit" >&2; exit 1; fi

# the validator accepts lowercase letters, digits and hyphens only, so everything else collapses;
# there is no date in this name, which is what makes a rewrite land on top of the old guide
SLUG=$(printf '%s' "$FEATURE" | tr '[:upper:]' '[:lower:]' \
  | sed -e 's/[^a-z0-9]/-/g' -e 's/--*/-/g' -e 's/^-//' -e 's/-$//' | cut -c1-60)
SLUG=${SLUG%-}
if [ -z "$SLUG" ]; then
  echo "fatal: the feature has no letters or digits to build a filename from" >&2; exit 1; fi

mkdir -p "$ARTIFACTS"
TARGET="$ARTIFACTS/$SLUG.md"
if [ -e "$TARGET" ]; then COLLISION=yes; else COLLISION=no; fi
EXISTING=$(find "$ARTIFACTS" -maxdepth 1 -type f -name '*.md' | wc -l | tr -d ' ')

echo "=== /write-guide telemetry ==="
echo "feature: $FEATURE"
echo "slug: $SLUG"
echo "target: $TARGET"
echo "collision: $COLLISION"
echo "existing_guides: $EXISTING"
echo "template: $TEMPLATE"
echo "validator: $VALIDATOR"

echo "--- guides already written ---"
find "$ARTIFACTS" -maxdepth 1 -type f -name '*.md' | sort | head -10 || true

if [ "$COLLISION" = yes ]; then
  echo "--- ask first ---"
  echo "$TARGET already exists; replacing it discards the guide that is there"
fi
echo "=============================="

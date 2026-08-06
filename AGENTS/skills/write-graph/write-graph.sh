#!/bin/bash
# =====================================================
# @file write-graph.sh - fan-out spec preflight sidecar
# =====================================================
# @description
# PAIR
# - sidecar for `/write-graph` — computes where the spec lands, then refuses to name an existing one
# - it measures only; the doc writes the file, since prose is the deliverable and not telemetry
# ARTIFACT
# - `docs/graphs/YYYY-MM-DD-operation-<slug>.md`, the shape `doc-graphs` documents and validates
# - the slug is the goal lowercased and kebabbed, so the filename reads back as the ask
# - a collision is reported and never resolved, since overwriting a spec loses the work inside it
# RUN
# - the goal arrives as arguments, and an empty one is fatal rather than a file called today
# - `mkdir -p` on the artifact directory is the one write it makes, and it is idempotent
# @see AGENTS.md, AGENTS/skills/write-graph/SKILL.md, AGENTS/skills/doc-graphs/SKILL.md, AGENTS/skills/doc-graphs/doc-graphs.sh, docs/graphs/

set -euo pipefail

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "fatal: not a git repository" >&2; exit 1; fi
cd "$(git rev-parse --show-toplevel)"

ARTIFACTS="docs/graphs"
TEMPLATE="AGENTS/skills/doc-graphs/SKILL.md"
VALIDATOR="AGENTS/skills/doc-graphs/doc-graphs.sh"
TODAY=$(date +%Y-%m-%d)

GOAL="$*"
if [ -z "$GOAL" ]; then
  echo "fatal: /write-graph needs a goal, as in: /write-graph import the backend repo" >&2; exit 1; fi

# the validator accepts letters, digits and hyphens only, so everything else collapses to a hyphen;
# the length cap keeps a rambling goal from becoming a filename nobody can read back
SLUG=$(printf '%s' "$GOAL" | tr '[:upper:]' '[:lower:]' \
  | sed -e 's/[^a-z0-9]/-/g' -e 's/--*/-/g' -e 's/^-//' -e 's/-$//' | cut -c1-60)
SLUG=${SLUG%-}
if [ -z "$SLUG" ]; then
  echo "fatal: the goal has no letters or digits to build a filename from" >&2; exit 1; fi

mkdir -p "$ARTIFACTS"
TARGET="$ARTIFACTS/$TODAY-operation-$SLUG.md"
if [ -e "$TARGET" ]; then COLLISION=yes; else COLLISION=no; fi
EXISTING=$(find "$ARTIFACTS" -maxdepth 1 -type f -name '*.md' | wc -l | tr -d ' ')

echo "=== /write-graph telemetry ==="
echo "goal: $GOAL"
echo "slug: $SLUG"
echo "target: $TARGET"
echo "collision: $COLLISION"
echo "existing_specs: $EXISTING"
echo "template: $TEMPLATE"
echo "validator: $VALIDATOR"

echo "--- most recent ---"
find "$ARTIFACTS" -maxdepth 1 -type f -name '*.md' | sort -r | head -3 || true

if [ "$COLLISION" = yes ]; then
  echo "--- stop ---"
  echo "a spec already holds this slug; rename the goal or open the existing file"
fi
echo "=============================="

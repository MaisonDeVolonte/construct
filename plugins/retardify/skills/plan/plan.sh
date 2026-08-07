#!/bin/bash
# =============================================
# @file plan.sh - staged plan preflight sidecar
# =============================================
# @description
# PAIR
# - sidecar for `/retardify:plan` — computes where the plan lands, then refuses to name an existing one
# - it measures only; the doc writes the file, since prose is the deliverable and not telemetry
# ARTIFACT
# - `docs/plans/YYYY-MM-DD-operation-<slug>.md`, the shape `doc-plans` documents and validates
# - the slug is the goal lowercased and kebabbed, so the filename reads back as the ask
# - a collision is reported and never resolved, since overwriting a plan loses the work inside it
# - open plans are listed too, since `blockers` names work found in other plans and not in this one
# RUN
# - the goal arrives as arguments, and an empty one is fatal rather than a file called today
# - `mkdir -p` on the artifact directory is the one write it makes, and it is idempotent
# @see AGENTS.md, plugins/retardify/skills/plan/SKILL.md, plugins/retardify/skills/plan/SKILL.md, plugins/retardify/skills/plan/doc-plans.sh, docs/plans/

set -euo pipefail

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "fatal: not a git repository" >&2; exit 1; fi
cd "$(git rev-parse --show-toplevel)"

ARTIFACTS="docs/plans"
TEMPLATE="plugins/retardify/skills/plan/SKILL.md"
VALIDATOR="plugins/retardify/skills/plan/doc-plans.sh"
TODAY=$(date +%Y-%m-%d)

GOAL="$*"
if [ -z "$GOAL" ]; then
  echo "fatal: /write-plan needs a goal, as in: /write-plan split the settings floor" >&2; exit 1; fi

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

echo "=== /write-plan telemetry ==="
echo "goal: $GOAL"
echo "slug: $SLUG"
echo "target: $TARGET"
echo "collision: $COLLISION"
echo "existing_plans: $EXISTING"
echo "template: $TEMPLATE"
echo "validator: $VALIDATOR"

# an unchecked box in an older plan is unshipped work, which is where a blocker comes from
echo "--- open plans (unchecked boxes) ---"
while IFS= read -r plan; do
  [ -z "$plan" ] && continue
  OPEN=$(grep -c '^- \[ \]' "$plan" 2>/dev/null || true)
  OPEN=${OPEN:-0}
  if [ "$OPEN" -gt 0 ]; then echo "$plan: $OPEN open"; fi
done < <(find "$ARTIFACTS" -maxdepth 1 -type f -name '*.md' | sort -r | head -10)

if [ "$COLLISION" = yes ]; then
  echo "--- stop ---"
  echo "a plan already holds this slug; rename the goal or open the existing file"
fi
echo "============================="

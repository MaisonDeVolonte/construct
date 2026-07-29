#!/bin/bash
# =============================================================
# @file gitbrutal.sh - adversarial doc-vs-reality audit sidecar
# =============================================================
# @description
# - sidecar for `@gitbrutal` — gathers telemetry for the brutal-honesty scorecard
# - seeds today's brutal file and reports its path, so the agent appends to a known target
# @see AGENTS.md, AGENTS/templates/git.md, AGENTS/git/gitbrutal.md, AGENTS/templates/brutal.md, docs/brutal/

set -euo pipefail

# check if in git repository
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "fatal: not a git repository" >&2; exit 1; fi

echo "=== @gitbrutal telemetry ==="

# one file per day, many scorecards per file — seeded here so the agent has a known target;
# paths anchor to the repo root, since the sidecar can be invoked from any subdirectory
echo "--- BRUTAL ARCHIVE ---"
ROOT=$(git rev-parse --show-toplevel)
TODAYS_BRUTAL="docs/brutal/$(date +%Y-%m-%d).md"
if [ ! -f "$ROOT/$TODAYS_BRUTAL" ];
then mkdir -p "$ROOT/docs/brutal"; echo "# $TODAYS_BRUTAL" > "$ROOT/$TODAYS_BRUTAL"; fi
echo "brutal_file: $TODAYS_BRUTAL"
echo "brutal_time: $(date '+%Y-%m-%d %H:%M')"
echo "brutal_count: $(grep -c '^## Brutal #' "$ROOT/$TODAYS_BRUTAL" 2>/dev/null || true)"

echo "--- REPO AGE & EFFORT ---"
FIRST_COMMIT=$(git log --reverse --format="%ad" --date=short | head -1 || echo "unknown")
TOTAL_COMMITS=$(git rev-list --count HEAD || echo "0")
echo "first commit: $FIRST_COMMIT"
echo "total commits: $TOTAL_COMMITS"

echo "--- COMMIT TYPE DISTRIBUTION (last 100) ---"
# Extracts conventional commit types to see if you actually follow them
git log -100 --format="%s" | awk -F'[(:]' '{print $1}' | sort | uniq -c | sort -nr | head -10 || echo "no commits"

echo "--- LOC BALANCE (ESTIMATE) ---"
# Rough check of App files vs Config/Infra files
APP_FILES=$(find src -type f 2>/dev/null | wc -l | tr -d ' ' || echo 0)
INFRA_FILES=$(find AGENTS .github webflow -maxdepth 2 -type f 2>/dev/null | wc -l | tr -d ' ' || echo 0)
ROOT_CONFIGS=$(find . -maxdepth 1 -type f \( -name "*.js" -o -name "*.json" -o -name "*.mjs" -o -name "*.ts" \) 2>/dev/null | wc -l | tr -d ' ' || echo 0)
echo "app source files: $APP_FILES"
echo "infra/agent files: $INFRA_FILES"
echo "root config files: $ROOT_CONFIGS"

echo "--- TEST REALITY ---"
TEST_FILES=$(find . \( -path ./node_modules -o -path ./content \) -prune -o \( -name "*.test.*" -o -name "*.spec.*" \) -type f -print 2>/dev/null | wc -l | tr -d ' ' || echo 0)
TODO_COUNT=$({ git grep -i "TODO" -- ':!AGENTS' 2>/dev/null || true; } | wc -l | tr -d ' ' || echo 0)
MIRROR_COUNT=$({ git grep -il "@mirror" -- 'content/**' 2>/dev/null || true; } | wc -l | tr -d ' ' || echo 0)
echo "test files: $TEST_FILES"
echo "unresolved TODOs: $TODO_COUNT"
echo "mirror pointer files: $MIRROR_COUNT"

echo "--- RISK HYGIENE ---"
# Check if sensitive or generated files slipped in
if git ls-files | grep -iq -e "\.env" -e "secret" -e "\.pem"; then
  echo "WARNING: POTENTIAL SECRETS TRACKED IN GIT"
  git ls-files | grep -i -e "\.env" -e "secret" -e "\.pem"
else
  echo "secrets check: clean"
fi

echo "============================"

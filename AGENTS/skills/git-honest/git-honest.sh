#!/bin/bash
# =============================================================
# @file git-honest.sh - adversarial doc-vs-reality audit sidecar
# =============================================================
# @description
# - sidecar for `@git-honest` — gathers telemetry for the honest scorecard
# - reports today's honest path and scorecard count, and never creates the file itself
# @see AGENTS.md, AGENTS/skills/check-skills/SKILL.md, AGENTS/skills/git-honest/SKILL.md, AGENTS/skills/doc-honest/SKILL.md, docs/honest/

set -euo pipefail

# check if in git repository
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "fatal: not a git repository" >&2; exit 1; fi

echo "=== @git-honest telemetry ==="

# one file per day, many scorecards per file — reported never created, so a run that produces
# no scorecard leaves nothing; paths anchor to the repo root, not the caller's dir
echo "--- HONEST ARCHIVE ---"
ROOT=$(git rev-parse --show-toplevel)
TODAYS_HONEST="docs/honest/$(date +%Y-%m-%d).md"
# no file yet means no scorecards yet, which is the count the agent numbers its first one from
if [ -f "$ROOT/$TODAYS_HONEST" ];
then HONEST_COUNT=$(grep -c '^## Honest #' "$ROOT/$TODAYS_HONEST" || true)
else HONEST_COUNT=0; fi
echo "honest_file: $TODAYS_HONEST"
echo "honest_time: $(date '+%Y-%m-%d %H:%M')"
echo "honest_count: $HONEST_COUNT"

echo "--- REPO AGE & EFFORT ---"
FIRST_COMMIT=$(git log --reverse --format="%ad" --date=short | head -1 || echo "unknown")
TOTAL_COMMITS=$(git rev-list --count HEAD || echo "0")
echo "first commit: $FIRST_COMMIT"
echo "total commits: $TOTAL_COMMITS"

echo "--- COMMIT TYPE DISTRIBUTION (last 100) ---"
# extracts conventional commit types to see if you actually follow them
git log -100 --format="%s" | awk -F'[(:]' '{print $1}' | sort | uniq -c | sort -nr | head -10 || echo "no commits"

echo "--- LOC BALANCE (ESTIMATE) ---"
# rough check of app source files against config and infra files
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
# check if sensitive or generated files slipped in
if git ls-files | grep -iq -e "\.env" -e "secret" -e "\.pem"; then
  echo "WARNING: POTENTIAL SECRETS TRACKED IN GIT"
  git ls-files | grep -i -e "\.env" -e "secret" -e "\.pem"
else
  echo "secrets check: clean"
fi

echo "============================"

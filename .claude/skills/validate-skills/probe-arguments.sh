#!/bin/bash
# ==========================================================
# @file probe-arguments.sh - free-text skills survive a quote
# ==========================================================
# @description
# - proves the `$ARGUMENTS` line of every free-text skill is quoted in its SKILL.md
# - an unquoted expansion dies on an apostrophe, which is how guidance actually gets typed
# - runs each named sidecar with an apostrophe goal, so the shape is proven and not just read
# - the path and flag skills stay unquoted on purpose, since they take several arguments
# - exits 1 on any failure, so ci can gate it beside validate-skills
# @see .claude/skills/validate-skills/validate-skills.sh, plugins/retardify/skills/plan/SKILL.md

set -uo pipefail

cd "${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}" || exit 1

# every skill whose argument is prose a human types, rather than a path or a flag
FREE_TEXT="
plugins/retardify/skills/plan
plugins/retardify/skills/graph
plugins/retardify/skills/quiz
plugins/retardify/skills/manual
plugins/gitgud/skills/deliver
"

APOSTROPHE="don't split the readme"
FAILURES=0

fail() { echo "FAIL $1"; FAILURES=$((FAILURES + 1)); }

for dir in $FREE_TEXT; do
  name=$(basename "$dir")
  doc="$dir/SKILL.md"
  sidecar="$dir/$name.sh"

  if ! grep -q "$name.sh \"\$ARGUMENTS\"" "$doc" 2>/dev/null; then
    fail "$doc invokes $name.sh with an unquoted \$ARGUMENTS"
  fi

  # only the skills that mint a new artifact from prose can be run with an arbitrary goal;
  # manual resolves an existing plan and deliver needs a dirty tree, so both exit for real reasons
  case "$name" in
    manual|deliver) continue;;
  esac
  if ! bash "$sidecar" "$APOSTROPHE" >/dev/null 2>&1; then
    fail "$sidecar exited nonzero on an apostrophe goal"
  fi
done

echo "=== probe-arguments ==="
echo "skills: $(echo "$FREE_TEXT" | grep -c .)"
echo "failures: $FAILURES"
[ "$FAILURES" -eq 0 ] && echo "every free-text skill quotes its arguments and survives an apostrophe"
exit $(( FAILURES > 0 ))

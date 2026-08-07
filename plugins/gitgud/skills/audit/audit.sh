#!/bin/bash
# =========================================================
# @file audit.sh - whole-repo condition telemetry sidecar
# =========================================================
# @description
# PAIR
# - sidecar for `/gitgud:audit` — reports what the repo is made of and where it has drifted
# - read-only and run only on the explicit command; it never mutates a tracked file
# - branch and remote state is `triage.sh`'s job, so this one never re-walks a branch
# - composition, pairing, shared drift and artifact freshness: what no other sidecar measures
# TRIGGER
# - it prints one telemetry block; the doc turns that into a numbered condition report
# - a plugin whose skill count is zero is a load failure rather than an empty plugin
# - an unpaired doc or sidecar is the shape error `tools/check-skills` grades in detail
# - a stale artifact directory means a writer skill stopped being run, not that it broke
# - shared drift is the check `secrets.sh` names in its own header, since duplication needs one
# @see AGENTS.md, plugins/gitgud/skills/audit/SKILL.md, plugins/gitgud/shared/triage.sh, plugins/gitgud/shared/handover.sh, tools/check-skills/README.md

set -euo pipefail

# probes: echo "key: $(some command 2>/dev/null || echo n/a)"

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)
SHARED=$(cd "$HERE/../../shared" 2>/dev/null && pwd || true)
if [ ! -f "$SHARED/handover.sh" ]; then
  echo "fatal: no plugins/gitgud/shared/handover.sh reachable from this sidecar" >&2; exit 1; fi
# shellcheck source=../../shared/handover.sh
. "$SHARED/handover.sh"

require_repo
cd "$(git rev-parse --show-toplevel)"

telemetry_open "git:audit"

# composition: what a fresh clone would actually load, counted from the tree rather than the docs
echo "--- composition ---"
telemetry_line "tracked_files" "$({ git ls-files || true; } | wc -l | tr -d ' ')"
telemetry_line "plugins" "$({ find plugins -maxdepth 1 -mindepth 1 -type d 2>/dev/null || true; } | wc -l | tr -d ' ')"
for p in plugins/*/; do
  [ -d "$p" ] || continue
  name=$(basename "$p")
  skills=$({ find "$p/skills" -maxdepth 1 -mindepth 1 -type d 2>/dev/null || true; } | wc -l | tr -d ' ')
  hooks=$({ find "$p/hooks" -maxdepth 1 -name '*.sh' 2>/dev/null || true; } | wc -l | tr -d ' ')
  telemetry_line "plugin_$name" "skills: $skills | hooks: $hooks"
done

# pairing: a doc without its script is a trigger that cannot run, and the reverse is dead code
echo "--- pairing ---"
DOCS=$({ find plugins -path '*/skills/*/SKILL.md' 2>/dev/null || true; } | wc -l | tr -d ' ')
ORPHAN_DOC=0; ORPHAN_SH=0
while IFS= read -r doc; do
  [ -n "$doc" ] || continue
  dir=$(dirname "$doc"); n=$(basename "$dir")
  [ -f "$dir/$n.sh" ] || ORPHAN_DOC=$((ORPHAN_DOC + 1))
done < <(find plugins -path '*/skills/*/SKILL.md' 2>/dev/null || true)
while IFS= read -r sh; do
  [ -n "$sh" ] || continue
  [ -f "$(dirname "$sh")/SKILL.md" ] || ORPHAN_SH=$((ORPHAN_SH + 1))
done < <(find plugins -path '*/skills/*/*.sh' 2>/dev/null || true)
telemetry_line "skill_docs" "$DOCS"
telemetry_line "docs_missing_sidecar" "$ORPHAN_DOC"
telemetry_line "sidecars_missing_doc" "$ORPHAN_SH"

# manifests: the catalog and the plugins disagreeing is what breaks an install rather than a load
echo "--- manifests ---"
for m in plugins/*/.claude-plugin/plugin.json; do
  [ -f "$m" ] || continue
  telemetry_line "manifest_$(basename "$(dirname "$(dirname "$m")")")" \
    "$(jq -r '"name: \(.name) | version: \(.version // "unset") | deps: \((.dependencies // []) | length)"' "$m" 2>/dev/null || echo 'unreadable')"
done
telemetry_line "catalog_entries" "$(jq -r '.plugins | length' .claude-plugin/marketplace.json 2>/dev/null || echo n/a)"

# shared: a plugin install copies one directory and never a sibling, so shared library code is
# duplicated per plugin rather than referenced. duplication only holds while the copies agree,
# and nothing else compares them: this is the check secrets.sh names in its own header
echo "--- shared ---"
COPIES=$({ find plugins -name 'secrets.sh' -type f 2>/dev/null || true; } | sort)
COUNT=$(printf '%s\n' "$COPIES" | grep -c . || true)
telemetry_line "secrets_copies" "$COUNT"
if [ "$COUNT" -gt 0 ]; then
  # hashed one at a time rather than as one argument list, since word-splitting an unquoted
  # expansion is a bash behaviour and this file should not depend on which shell sources it
  DISTINCT=$(printf '%s\n' "$COPIES" \
    | while IFS= read -r f; do [ -n "$f" ] && md5 -q "$f" 2>/dev/null; done \
    | sort -u | grep -c . || true)
  if [ "$DISTINCT" -eq 1 ]; then
    telemetry_line "secrets_drift" "none; all $COUNT copies are byte identical"
  else
    telemetry_line "secrets_drift" "DRIFT: $DISTINCT versions across $COUNT copies"
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      telemetry_line "  $f" "$(md5 -q "$f" 2>/dev/null | cut -c1-8)"
    done <<< "$COPIES"
  fi
fi

# artifacts: a directory whose newest file is old means its writer stopped being run
echo "--- artifacts ---"
for d in docs/*/; do
  [ -d "$d" ] || continue
  count=$({ find "$d" -name '*.md' 2>/dev/null || true; } | wc -l | tr -d ' ')
  latest=$({ find "$d" -name '*.md' 2>/dev/null || true; } | sort | tail -1)
  telemetry_line "$(basename "$d")" "files: $count | latest: ${latest:-none}"
done

echo "--- end ---"
block_close

handover_open "git:audit"
handover_note "branch, remote and team state is a separate read; this sidecar never re-walks them"
handover_cmd "bash plugins/gitgud/shared/triage.sh"
handover_note "shape errors are graded in detail by the repo-local tool, which is not a skill"
handover_cmd "bash tools/check-skills/check-skills.sh"
block_close

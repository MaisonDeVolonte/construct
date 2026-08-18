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
# - an unpaired doc or sidecar is the shape error `/skills` grades in detail
# - a stale artifact directory means a writer skill stopped being run, not that it broke
# - shared drift is the check `secrets.sh` names in its own header, since duplication needs one
# ARTIFACT
# - `.construct/gitgud/audit/YYYY-MM-DD.md`, one file per day, holding the report and its telemetry
# - this skill owns the git kind outright: it names the target, and grades every entry that landed
# - `triage.sh` used to report the target and no doc ever instructed the write, so nothing wrote it
# - gitignored in this repo; read-only still holds, since no TRACKED file is ever touched
# @see plugins/gitgud/skills/audit/SKILL.md, plugins/gitgud/shared/triage.sh, plugins/gitgud/shared/handover.sh, .claude/skills/validate-skills/SKILL.md, .construct/gitgud/audit/

set -euo pipefail

# the doc is read only after this has already run, so help is refused here or not at all; the doc's
# own '## Help' section owns the output, which is why this prints a marker rather than a usage text
case " $* " in *" --help "*|*" -h "*) echo "help: requested"; exit 0;; esac

# the smoke case proves this file parses and its guards return; /test-skills reads the sources,
# the @see paths and the tool guards statically, so nothing here runs a step of the skill
case " $* " in *" --test "*) echo "test: ok"; exit 0;; esac

# priced and gated here for the same reason help is: the doc is read only once this has already run.
# the cost is the tree it walks, so the estimate measures that rather than naming a fixed duration
ESTIMATE_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo .)
ESTIMATE_SCALE=$({ git -C "$ESTIMATE_ROOT" ls-files 2>/dev/null || true; } | wc -l | tr -d ' ')
echo "estimate: scales with the ${ESTIMATE_SCALE:-0} tracked files it walks, counting not executing"
case " $* " in *" --confirm "*) ;; *) echo "confirm: required"; exit 0;; esac

# probes: echo "key: $(some command 2>/dev/null || echo n/a)"

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)
SHARED=$(cd "$HERE/../../shared" 2>/dev/null && pwd || true)
if [ ! -f "$SHARED/handover.sh" ]; then
  echo "fatal: no plugins/gitgud/shared/handover.sh reachable from this sidecar" >&2; exit 1; fi
# shellcheck source=../../shared/handover.sh
. "$SHARED/handover.sh"

require_repo
ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"

telemetry_open "gitgud:audit"

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
# one directory per skill, nested under its plugin, so the walk runs two levels deep
for d in .construct/*/*/; do
  [ -d "$d" ] || continue
  label=${d#.construct/}; label=${label%/}
  count=$({ find "$d" -name '*.md' 2>/dev/null || true; } | wc -l | tr -d ' ')
  latest=$({ find "$d" -name '*.md' 2>/dev/null || true; } | sort | tail -1)
  telemetry_line "$label" "files: $count | latest: ${latest:-none}"
done

# ==============
# ARTIFACT
#   this skill's own dated artifact, graded here so nothing outside this file decides its shape
#   the shape lives in this skill's SKILL.md and the labels below are what this sidecar emits
# ==============
ARTIFACT_KIND="git"
ARTIFACT_SECTIONS=$'state\nfindings\nresolutions\ntelemetry'
# one label per grading rule the SKILL.md states, so a finding names the rule that caught it
CONDITION_LABELS='Load Failure|Orphan Pair|Unpinned Version|Catalog Gap|Shared Drift|Missing Copy|Stale Artifact'
# the branch labels this kind carried before /gitgud:audit took it over; entries written under them
# are still in the archive and an audit is never edited after the fact, so both sets stay valid
LEGACY_LABELS='Ghost Branch|Local Clutter|Rebase Absorbed|Conflict Risk|Dirty Trunk|Uncommitted Tree'
ARTIFACT_LABELS="$CONDITION_LABELS|$LEGACY_LABELS"
ARTIFACT_MAX_WIDTH=100

# this library prints telemetry rather than collecting findings, so the two adapt to that
artifact_err()  { echo "artifact_ERROR: $1:$2 $3 — $4"; }
artifact_warn() { echo "artifact_WARN:  $1:$2 $3 — $4"; }

# emit "START<TAB>END<TAB>HEADING" per `## ` entry, so a check can scope itself to one entry
artifact_entries() {
  awk '
    /^## / { if (start) print start "\t" NR - 1 "\t" heading; start = NR; heading = substr($0, 4); next }
    END { if (start) print start "\t" NR "\t" heading }
  ' "$1"
}

# emit "LINENO<TAB>TEXT" for one entry's `### <name>` block; any heading closes it, so a malformed
# entry cannot bleed its body into the entry below
artifact_subsection() {
  awk -v s="$2" -v e="$3" -v want="### $4" '
    NR < s || NR > e { next }
    $0 == want { inside = 1; next }
    /^##+ / { inside = 0 }
    inside { print NR "\t" $0 }
  ' "$1"
}

check_artifact_file() {
  local rel=$1 file=$2
  local base date start end heading number stamp label actual body fenced
  local expected=1 previous='' count=0 found=0 fixed=0 lineno text infence=0
  base=$(basename "$rel" .md)
  date=$(printf '%s' "$base" | cut -c1-10)

  # "one file per day" — the date keeps it append-only and diffable against yesterday
  if ! printf '%s' "$base.md" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}\.md$'; then
    artifact_err "$rel" 1 filename "one file per day, named YYYY-MM-DD.md under its kind"
  fi

  # the agent opens the file with its own path as the h1, so a mismatch means it was copied
  if [ "$(sed -n '1p' "$file")" != "# $rel" ]; then
    artifact_err "$rel" 1 header "line 1 must read '# $rel'"
  fi

  # a fence left unclosed swallows every entry after it, so count before reading any section
  fenced=$(grep -cE '^[[:space:]]*```' "$file" || true)
  if [ $((fenced % 2)) -ne 0 ]; then
    artifact_err "$rel" 1 fences "$fenced fence markers; one is unclosed"
  fi

  # scaffolding left in a shipped file reads as fact to everyone downstream
  while IFS= read -r text; do
    [ -n "$text" ] || continue
    artifact_err "$rel" "${text%%:*}" placeholder "template scaffolding survived: $(printf '%s' "${text#*:}" \
      | grep -oE 'YYYY-MM-DD|HH:MM|\*example:\*|repeat the above format' | head -n 1)"
  done < <(grep -nE 'YYYY-MM-DD|HH:MM|\*example:\*|repeat the above format' "$file" || true)

  # "lines carry a single clause, capped at 100" — telemetry is pasted by contract, so it is exempt
  lineno=0
  while IFS= read -r text; do
    lineno=$((lineno + 1))
    case "$text" in '```'*) infence=$((1 - infence)); continue;; esac
    [ "$infence" -eq 1 ] && continue
    if [ ${#text} -gt "$ARTIFACT_MAX_WIDTH" ]; then
      artifact_err "$rel" "$lineno" width "${#text} chars; the cap is $ARTIFACT_MAX_WIDTH"
    fi
  done < "$file"

  while IFS=$'\t' read -r start end heading; do
    count=$((count + 1))
    # "appended each run" — numbering and timestamps are the append order, and the kind pairs the
    # heading to the file, so a settings entry in the git file is caught rather than merged
    if ! printf '%s' "$heading" \
      | grep -qE '^[A-Z][A-Za-z]* Audit #[0-9]+: [0-9]{4}-[0-9]{2}-[0-9]{2} ([01][0-9]|2[0-3]):[0-5][0-9]$'
    then
      artifact_err "$rel" "$start" entry_heading "entries read '## <Kind> Audit #N: YYYY-MM-DD HH:MM'"
      continue
    fi
    number=$(printf '%s' "$heading" | sed -n 's/^[A-Za-z]\{1,\} Audit #\([0-9]\{1,\}\):.*/\1/p')
    stamp=$(printf '%s' "$heading" | sed -n 's/^[A-Za-z]\{1,\} Audit #[0-9]\{1,\}: \(.*\)$/\1/p')
    label=$(printf '%s' "$heading" | sed -n 's/^\([A-Za-z]\{1,\}\) Audit #.*/\1/p' | tr '[:upper:]' '[:lower:]')
    if [ "$label" != "$ARTIFACT_KIND" ]; then
      artifact_err "$rel" "$start" entry_kind "a $label entry in the file for $ARTIFACT_KIND"
    fi
    if [ "$number" -ne "$expected" ]; then
      artifact_err "$rel" "$start" entry_numbering "entry $number where $expected was expected"
    fi
    expected=$((number + 1))
    case "$stamp" in
      "$date "*) ;;
      *) artifact_err "$rel" "$start" entry_date "timestamped $stamp in the file for $date";;
    esac
    if [ -n "$previous" ] && [[ "$stamp" < "$previous" ]]; then
      artifact_warn "$rel" "$start" entry_order "timestamp precedes the entry above it; runs append"
    fi
    previous=$stamp

    actual=$(awk -v s="$start" -v e="$end" 'NR >= s && NR <= e && /^### / { print substr($0, 5) }' "$file")
    if [ "$actual" != "$ARTIFACT_SECTIONS" ]; then
      artifact_err "$rel" "$start" section_order "got $(printf '%s' "$actual" | tr '\n' '>' | sed 's/>$//')"
    fi

    found=0
    while IFS=$'\t' read -r lineno text; do
      printf '%s' "$text" | grep -qE '^- ' || continue
      found=$((found + 1))
      if ! printf '%s' "$text" | grep -qE '^- \*\*[^*]+\*\* — .'; then
        artifact_err "$rel" "$lineno" finding_shape 'findings read "- **Label** — what is wrong, and on what"'
        continue
      fi
      label=$(printf '%s' "$text" | sed -n 's/^- \*\*\([^*]*\)\*\*.*/\1/p')
      if ! printf '%s' "$label" | grep -qE "^($ARTIFACT_LABELS)\$"; then
        artifact_warn "$rel" "$lineno" finding_label "'$label' is not a label this sidecar emits"
      fi
    done < <(artifact_subsection "$file" "$start" "$end" findings)
    if [ "$found" -eq 0 ]; then
      artifact_warn "$rel" "$start" no_findings "no findings listed; a clean run says so in one line"
    fi

    fixed=0
    while IFS=$'\t' read -r lineno text; do
      printf '%s' "$text" | grep -qE '^- \[[ x]\] ' || continue
      fixed=$((fixed + 1))
      if ! printf '%s' "$text" | grep -qE '`|/[a-z]+:'; then
        artifact_warn "$rel" "$lineno" resolution_shape "name a command or a slash command, not prose"
      fi
    done < <(artifact_subsection "$file" "$start" "$end" resolutions)
    if [ "$found" -ne "$fixed" ]; then
      artifact_err "$rel" "$start" resolution_parity "$found finding(s), $fixed resolution(s); one each"
    fi

    body=$(artifact_subsection "$file" "$start" "$end" telemetry | cut -f2- | grep -v '^[[:space:]]*$' || true)
    if [ -z "$body" ]; then
      artifact_err "$rel" "$start" telemetry "telemetry holds the raw sidecar output, never blank"
    elif [ "$(printf '%s' "$body" | grep -c '^```' || true)" -lt 2 ]; then
      artifact_warn "$rel" "$start" telemetry "fence the raw output, so a reader can tell it from prose"
    fi
  done < <(artifact_entries "$file")

  if [ "$count" -eq 0 ]; then
    artifact_warn "$rel" 1 empty "seeded, holds no entries yet"
  fi
}

# grade every file of this kind, not only the one today's run appends to: an older defect stays a
# defect, and nothing else reads these files
check_artifact() {
  local dir=$1 found resolved
  dir=${dir%/}
  case "$dir" in *.md) dir=$(dirname "$dir");; esac
  resolved=$dir
  if [ ! -d "$resolved" ] && [ -n "${ROOT:-}" ] && [ -d "$ROOT/$dir" ]; then resolved="$ROOT/$dir"; fi
  [ -d "$resolved" ] || return 0
  for found in "$resolved"/*.md; do
    [ -f "$found" ] || continue
    check_artifact_file "${found#"${ROOT:-}"/}" "$found"
  done
}

# archive: one file per day, many audits per file — reported never created, so this sidecar names
# the target and the number the entry should carry, and the agent writes it
echo "--- archive ---"
TODAYS_AUDIT=".construct/gitgud/audit/$(date +%Y-%m-%d).md"
# no file yet means no audits yet, which is the count the agent numbers its first one from
if [ -f "$ROOT/$TODAYS_AUDIT" ];
then AUDIT_COUNT=$(grep -c '^## Git Audit #' "$ROOT/$TODAYS_AUDIT" || true)
else AUDIT_COUNT=0; fi
telemetry_line "audit_file" "$TODAYS_AUDIT"
telemetry_line "audit_count" "$AUDIT_COUNT"
telemetry_line "next_audit" "$((AUDIT_COUNT + 1))"
telemetry_line "timestamp" "$(date '+%Y-%m-%d %H:%M')"
check_artifact ".construct/gitgud/audit"

echo "--- end ---"
block_close

handover_open "gitgud:audit"
handover_note "branch, remote and team state is a separate read; this sidecar never re-walks them"
handover_cmd "bash plugins/gitgud/shared/triage.sh"
handover_note "shape errors are graded in detail by /skills, the maintainer skill this repo keeps"
handover_cmd "bash .claude/skills/validate-skills/validate-skills.sh"
block_close

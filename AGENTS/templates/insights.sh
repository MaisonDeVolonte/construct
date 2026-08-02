#!/bin/bash
# ==========================================================
# @file insights.sh - opportunity report validator sidecar
# ==========================================================
# @description
# - sidecar for `insights.md` — asserts a report archive matches the template that documents it
# - one check per machine-checkable rule; every rule needing judgement prints as a human checklist
# - ERROR breaks a rule the template states outright; WARN names a smell the template tolerates
# - defaults to every file in `docs/insights/`; pass files or a directory to scope it
# - `--strict` promotes warnings to errors, `--keep` preserves scratch; exits 1 on any error
# @see AGENTS.md, AGENTS/security/secrets.sh, AGENTS/templates/insights.md, AGENTS/git/gitinsights.md, AGENTS/templates/plans.sh, docs/insights/

set -euo pipefail

# ==============
# PREFLIGHT
# ==============
# the shared scan sits beside this file, not beside the repo being scanned: resolve them before
# anything cds to a repo root, since BASH_SOURCE arrives relative and would follow that cd
SHARED=$(cd "$(dirname "${BASH_SOURCE[0]}")/../security" 2>/dev/null && pwd || true)
if [ ! -f "$SHARED/secrets.sh" ]; then
  echo "fatal: no AGENTS/security/secrets.sh beside this sidecar" >&2; exit 1; fi
# shellcheck source=../security/secrets.sh
. "$SHARED/secrets.sh"

# character counts, not byte counts: bash's ${#var} is multibyte-aware under a utf-8 locale, and
# every em dash in a report is 3 bytes — a byte count would flag lines that are legally under the cap
UTF8_LOCALE=$(locale -a 2>/dev/null | grep -iE '^(C|en_US)\.(utf-?8)$' | head -n 1 || true)
if [ -n "$UTF8_LOCALE" ]; then export LC_ALL="$UTF8_LOCALE"; fi

MAX_WIDTH=100
STRICT=0
KEEP=0
TEMPLATE="AGENTS/templates/insights.md"
ARTIFACTS="docs/insights"

# the subsections every report carries, which is the one thing every entry must agree on
EXPECTED_SECTIONS=$'sources\nobservations\nopportunities\ncarried'

# the urgent/important matrix, in the template's order; all four quadrants are always reported,
# because an empty quadrant is itself a finding about where the work is going
EXPECTED_QUADRANTS=$'urgent and important\nurgent but not important\nnot urgent but important\nnot urgent or important'

# "a Q1 entry that survives three reports has stopped being urgent in practice, say so"
STALE_AFTER=3

REPORTS=()
for arg in "$@"; do
  case "$arg" in
    --strict) STRICT=1;;
    --keep) KEEP=1;;
    -h|--help) sed -n '2,11p' "$0"; exit 0;;
    -*) echo "fatal: unknown flag $arg" >&2; exit 1;;
    *) REPORTS+=("$arg");;
  esac
done

# no paths given: scan the whole artifact directory, anchored to the repo root so the default
# works from any subdirectory — same posture as the @git* sidecars
if [ ${#REPORTS[@]} -eq 0 ]; then
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "fatal: not a git repository, and no paths given" >&2; exit 1; fi
  cd "$(git rev-parse --show-toplevel)"
  if [ ! -d "$ARTIFACTS" ]; then echo "fatal: no $ARTIFACTS/ to scan" >&2; exit 1; fi
  REPORTS=("$ARTIFACTS"/*.md)
fi

# a directory argument expands to the report files inside it
EXPANDED=()
for path in "${REPORTS[@]}"; do
  if [ -d "$path" ]; then
    for nested in "$path"/*.md; do [ -f "$nested" ] && EXPANDED+=("$nested"); done
  elif [ -f "$path" ]; then EXPANDED+=("$path")
  else echo "fatal: no such report file: $path" >&2; exit 1; fi
done
REPORTS=("${EXPANDED[@]}")

# repo-local scratch: the sandbox denies writes outside cwd, and macos mktemp ignores TMPDIR
TMPROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)/tmp"
TMPTAG=$(basename "${BASH_SOURCE[0]}" .sh)
mkdir -p "$TMPROOT"

# findings collect as "SEV|file|line|category|detail" — line is its own field so the report can
# sort numerically; joining it to the path first sorts 121 above 31. the run fails on ERROR only
FINDINGS=$(mktemp "$TMPROOT/$TMPTAG-findings.XXXXXX")
# a failed run leaves scratch behind to read; --keep does the same after a clean one
cleanup() { st=$?; if [ "$KEEP" -eq 0 ] && [ "$st" -eq 0 ]; then rm -f "$FINDINGS"; fi; }
trap cleanup EXIT

err()  { printf 'ERROR|%s|%s|%s|%s\n' "$1" "$2" "$3" "$4" >> "$FINDINGS"; }
warn() { printf 'WARN|%s|%s|%s|%s\n' "$1" "$2" "$3" "$4" >> "$FINDINGS"; }

# emit "START<TAB>END<TAB>HEADING" per `## ` entry, so every check can scope itself to one report
entries() {
  awk '
    /^## / { if (start) print start "\t" NR - 1 "\t" heading; start = NR; heading = substr($0, 4); next }
    END { if (start) print start "\t" NR "\t" heading }
  ' "$1"
}

# emit "LINENO<TAB>TEXT" for every line inside one entry's `### <name>` block; any heading closes
# it, so a malformed entry cannot bleed its body into the report that follows
subsection() {
  awk -v s="$2" -v e="$3" -v want="### $4" '
    NR < s || NR > e { next }
    $0 == want { inside = 1; next }
    /^##+ / { inside = 0 }
    inside { print NR "\t" $0 }
  ' "$1"
}

# ==============
# CHECKS
#   each takes a report path and appends findings; to add one, write a function and list it below
# ==============

# "one insights file per day" — the date in the name is what makes a recurring opportunity visible
check_filename() {
  local file=$1 base dir
  base=$(basename "$file")
  dir=$(dirname "$file")
  if ! printf '%s' "$base" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}\.md$'; then
    err "$file" 1 filename "one insights file per day, named YYYY-MM-DD.md"
  fi
  case "$dir" in
    "$ARTIFACTS"|"./$ARTIFACTS"|*"/$ARTIFACTS") ;;
    *) warn "$file" 1 location "report archives live in $ARTIFACTS/";;
  esac
}

# "tracked in git"
check_tracked() {
  local file=$1
  if ! git ls-files --error-unmatch "$file" >/dev/null 2>&1; then
    warn "$file" 1 untracked "reports are tracked in git; this one is not committed yet"
  fi
}

# the sidecar seeds the file with its own path as the h1, so a mismatch means the file was copied
# from another day — and a recurring opportunity is invisible once two days share a file
check_header() {
  local file=$1 expected actual
  expected="# $ARTIFACTS/$(basename "$file")"
  actual=$(sed -n '1p' "$file")
  if [ "$actual" != "$expected" ]; then
    err "$file" 1 header "line 1 must read '$expected'"
  fi
}

# "appended each run, many reports per file" — numbering and timestamps are the append order
check_entries() {
  local file=$1 start end heading number stamp expected=1 previous='' count=0 date
  date=$(basename "$file" .md)
  while IFS=$'\t' read -r start end heading; do
    count=$((count + 1))
    if ! printf '%s' "$heading" \
      | grep -qE '^Insight #[0-9]+: [0-9]{4}-[0-9]{2}-[0-9]{2} ([01][0-9]|2[0-3]):[0-5][0-9]$'; then
      err "$file" "$start" entry_heading "entries read '## Insight #N: YYYY-MM-DD HH:MM'"
      continue
    fi
    number=$(printf '%s' "$heading" | sed -n 's/^Insight #\([0-9]\{1,\}\):.*/\1/p')
    stamp=$(printf '%s' "$heading" | sed -n 's/^Insight #[0-9]\{1,\}: \(.*\)$/\1/p')
    if [ "$number" -ne "$expected" ]; then
      err "$file" "$start" entry_numbering "report $number where $expected was expected"
    fi
    expected=$((number + 1))
    case "$stamp" in
      "$date "*) ;;
      *) err "$file" "$start" entry_date "timestamped $stamp in the file for $date";;
    esac
    if [ -n "$previous" ] && [[ "$stamp" < "$previous" ]]; then
      warn "$file" "$start" entry_order "timestamp precedes the report above it; each run appends"
    fi
    previous=$stamp
  done < <(entries "$file")
  if [ "$count" -eq 0 ]; then
    warn "$file" 1 empty "seeded, holds no reports yet"
  fi
}

# the four subsections, in the template's order; a report without `carried` cannot show what keeps
# getting skipped, which is the only thing the archive is for
check_subsections() {
  local file=$1 start end heading actual
  while IFS=$'\t' read -r start end heading; do
    actual=$(awk -v s="$start" -v e="$end" 'NR >= s && NR <= e && /^### / { print substr($0, 5) }' "$file")
    if [ -z "$actual" ]; then
      err "$file" "$start" section_order "no ### subsections; expected $(printf '%s' "$EXPECTED_SECTIONS" | tr '\n' '>' | sed 's/>$//')"
    elif [ "$actual" != "$EXPECTED_SECTIONS" ]; then
      err "$file" "$start" section_order "got $(printf '%s' "$actual" | tr '\n' '>' | sed 's/>$//')"
    fi
  done < <(entries "$file")
}

# "which streams fed this report, and the log range read" — without the range, nobody can tell
# whether a later report re-read the same days or moved on
check_sources() {
  local file=$1 start end heading body
  while IFS=$'\t' read -r start end heading; do
    body=$(subsection "$file" "$start" "$end" sources | cut -f2- | grep -v '^[[:space:]]*$' || true)
    if [ -z "$body" ]; then
      err "$file" "$start" sources_empty "name the streams that fed the report and the log range read"
      continue
    fi
    if ! printf '%s' "$body" | grep -qE '[0-9]{4}-[0-9]{2}-[0-9]{2}'; then
      warn "$file" "$start" sources_range "no log range; a dated range is what makes the next report honest"
    fi
  done < <(entries "$file")
}

# "`observations` are what the three streams found" — a stream reported something specific or it
# reported nothing, so an observation naming neither a file nor a count is not an observation
check_observations() {
  local file=$1 start end heading lineno text count
  while IFS=$'\t' read -r start end heading; do
    count=0
    while IFS=$'\t' read -r lineno text; do
      case "$text" in "- "*) ;; *) continue;; esac
      count=$((count + 1))
      if ! printf '%s' "$text" | grep -qE '`|[0-9]'; then
        warn "$file" "$lineno" unspecific "name the file, path or count the stream actually surfaced"
      fi
    done < <(subsection "$file" "$start" "$end" observations)
    if [ "$count" -eq 0 ]; then
      err "$file" "$start" observations_empty "no observations; the report has nothing to reason from"
    fi
  done < <(entries "$file")
}

# "`opportunities` sort onto the urgent/important matrix, and name the file they touch" — all four
# quadrants, in order, because a missing quadrant reads as "nothing here" when it means "unsorted"
check_opportunities() {
  local file=$1 start end heading lineno text label actual quadrant items
  while IFS=$'\t' read -r start end heading; do
    actual=''
    quadrant=''
    items=0
    while IFS=$'\t' read -r lineno text; do
      case "$text" in
        '**'*':**')
          if [ -n "$quadrant" ] && [ "$items" -eq 0 ]; then
            warn "$file" "$lineno" quadrant_empty "$quadrant holds nothing; write none rather than leaving it blank"
          fi
          label=$(printf '%s' "$text" | sed -n 's/^\*\*\(.*\):\*\*$/\1/p')
          actual="$actual$label"$'\n'
          quadrant=$label
          items=0
          continue;;
        # an explicit `- none` fills a quadrant without naming a file, and is the honest way to
        # report that nothing sorted into it
        "- none"*) items=$((items + 1)); continue;;
        "- "*) ;;
        *) continue;;
      esac
      items=$((items + 1))
      if ! printf '%s' "$text" | grep -q '`'; then
        warn "$file" "$lineno" no_file "name the file the opportunity touches, in ticks"
      fi
    done < <(subsection "$file" "$start" "$end" opportunities)
    if [ -n "$quadrant" ] && [ "$items" -eq 0 ]; then
      warn "$file" "$start" quadrant_empty "$quadrant holds nothing; write none rather than leaving it blank"
    fi
    actual=${actual%$'\n'}
    if [ "$actual" != "$EXPECTED_QUADRANTS" ]; then
      err "$file" "$start" quadrants "all four quadrants, in order; got $(printf '%s' "$actual" | tr '\n' '>' | sed 's/>$//')"
    fi
  done < <(entries "$file")
}

# "opportunities restated from an earlier report, with how many reports they have survived" — the
# count is the finding, and a count at or past the threshold is the template's own escalation
check_carried() {
  local file=$1 start end heading lineno text count survived
  while IFS=$'\t' read -r start end heading; do
    count=0
    while IFS=$'\t' read -r lineno text; do
      case "$text" in
        *[![:space:]]*) ;;
        *) continue;;
      esac
      count=$((count + 1))
      # nothing carried is a real state, and saying so is not the same as leaving it blank
      case "$text" in -[[:space:]]none*|none*) continue;; esac
      survived=$(printf '%s' "$text" | sed -n 's/.*carried \([0-9]\{1,\}\) report.*/\1/p')
      if [ -z "$survived" ]; then
        warn "$file" "$lineno" carried_count "say how many reports it has survived: carried N reports"
        continue
      fi
      if [ "$survived" -ge "$STALE_AFTER" ]; then
        warn "$file" "$lineno" carried_stale "survived $survived reports; call it what it is in practice"
      fi
    done < <(subsection "$file" "$start" "$end" carried)
    if [ "$count" -eq 0 ]; then
      warn "$file" "$start" carried_empty "write none; a blank carried section reads as unchecked"
    fi
  done < <(entries "$file")
}

# "`lines` should contain a single clause/fact/action, limited to 100 characters"
check_width() {
  local file=$1 lineno=0 line
  while IFS= read -r line; do
    lineno=$((lineno + 1))
    if [ ${#line} -gt "$MAX_WIDTH" ]; then
      err "$file" "$lineno" width "${#line} chars; the cap is $MAX_WIDTH"
    fi
  done < "$file"
}

# "skip the raw sidecar dump; keep the read of it, not the printout" — a fenced block in a report
# is almost always that dump, and an unclosed fence swallows every report after it
check_fences() {
  local file=$1 hit count=0
  while IFS= read -r hit; do
    if [ -z "$hit" ]; then continue; fi
    count=$((count + 1))
    if [ $((count % 2)) -eq 1 ]; then
      warn "$file" "${hit%%:*}" sidecar_dump "keep the read of the sidecar output, not the printout"
    fi
  done < <(grep -nE '^[[:space:]]*```' "$file" || true)
  if [ $((count % 2)) -ne 0 ]; then
    err "$file" 1 fences "$count fence markers; one is unclosed"
  fi
}

# scaffolding left in a shipped artifact reads as fact to everyone downstream
check_placeholders() {
  local file=$1 hit token
  while IFS= read -r hit; do
    if [ -z "$hit" ]; then continue; fi
    token=$(printf '%s' "${hit#*:}" \
      | grep -oE 'YYYY-MM-DD|HH:MM|\*example:\*|hyphen-delimited list|repeat the above format' | head -n 1)
    err "$file" "${hit%%:*}" placeholder "template scaffolding survived: $token"
  done < <(grep -nE 'YYYY-MM-DD|HH:MM|\*example:\*|hyphen-delimited list|repeat the above format' "$file" || true)
}


# --- run list (add new checks here) ---
for report in "${REPORTS[@]}"; do
  check_filename      "$report"
  check_tracked       "$report"
  check_header        "$report"
  check_entries       "$report"
  check_subsections   "$report"
  check_sources       "$report"
  check_observations  "$report"
  check_opportunities "$report"
  check_carried       "$report"
  check_width         "$report"
  check_fences        "$report"
  check_placeholders  "$report"
  scan_secrets        "$report"
done

# ==============
# TELEMETRY
# ==============
ERRORS=$(grep -c '^ERROR|' "$FINDINGS" || true)
WARNINGS=$(grep -c '^WARN|' "$FINDINGS" || true)
SECRETS=$(grep -c '|secret|' "$FINDINGS" || true)

cat <<EOF

=== insights.sh sidecar ===
template: $TEMPLATE
scanned: ${#REPORTS[@]} report file(s)
width_cap: $MAX_WIDTH chars
errors: $ERRORS
warnings: $WARNINGS
secrets: $SECRETS
--- findings ---
EOF

if [ "$ERRORS" -eq 0 ] && [ "$WARNINGS" -eq 0 ]; then
  echo "none — every machine-checkable rule holds"
else
  sort -t'|' -k1,1 -k2,2 -k3,3n "$FINDINGS" \
    | awk -F'|' '{ printf "%-5s %-50s %-17s %s\n", $1, $2 ":" $3, $4, $5 }'
fi

if [ "$SECRETS" -gt 0 ]; then
  cat <<EOF
--- secrets ---
STOP: $SECRETS unambiguous credential match(es) above
- do NOT truncate or edit anything yet; ask the user which match is real and what to do about it
- a key that already reached a commit is leaked, and truncating the file does not un-leak it
- rotate the credential first, then agree what the file should say in its place
EOF
fi
cat <<'EOF'
--- needs a human (template rules no script can judge) ---
- reports capture the opportunity surface at a moment in time, and are never edited after the fact
- observations are what the streams found; opportunities are what to do about it, never the reverse
- an opportunity that recurs across dated files is a finding; restate it, never edit the older report
- a Q1 entry that survives three reports has stopped being urgent in practice, so say that outright
- each opportunity sorts onto the matrix by consequence, not by how interesting it is to work on
- skip the raw sidecar dump; keep the read of it, not the printout
- err on the side of brevity, not completeness
- a key that reached a commit is already leaked; rotate it before rewriting anything
========================
EOF

if [ "$ERRORS" -gt 0 ]; then exit 1; fi
if [ "$STRICT" -eq 1 ] && [ "$WARNINGS" -gt 0 ]; then exit 1; fi
exit 0

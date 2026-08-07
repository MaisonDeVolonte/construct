#!/bin/bash
# ===============================================================================================
# @file review.sh - adversarial review sidecar: gathers the telemetry, then grades the scorecards
# ===============================================================================================
# @description
# PAIR
# - the only sidecar for `/retardify:review`, which owns both halves of its own artifact
# - the doc carries the shape; this file names where it lands and grades what landed there
# - one skill is one SKILL.md and one sidecar, so nothing outside this pair decides its shape
# RUN
# - no flag runs the trigger half, so every existing invocation is unchanged
# - `--check [paths]` runs the validator half; with no paths it grades the whole artifact dir
# - ERROR breaks a rule the doc states outright; WARN names a smell the doc tolerates
# @see plugins/retardify/skills/review/SKILL.md, README.md, .operator/reviews/, tools/check-skills/README.md, plugins/retardify/skills/review/review.sh, plugins/retardify/shared/secrets.sh

set -euo pipefail

# `--check` selects the validator half; anything else is the trigger, so the doc's own
# bang-injected call keeps working untouched
if [ "${1:-}" = "--check" ]; then
  shift
else
  # check if in git repository
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "fatal: not a git repository" >&2; exit 1; fi

  echo "=== /retardify:review telemetry ==="

  # one file per day, many scorecards per file — reported never created, so a run that produces
  # no scorecard leaves nothing; paths anchor to the repo root, not the caller's dir
  echo "--- REVIEW ARTIFACT ---"
  ROOT=$(git rev-parse --show-toplevel)
  TODAYS_REVIEW=".operator/reviews/$(date +%Y-%m-%d).md"
  # no file yet means no scorecards yet, which is the count the agent numbers its first one from
  if [ -f "$ROOT/$TODAYS_REVIEW" ];
  then REVIEW_COUNT=$(grep -c '^## Review #' "$ROOT/$TODAYS_REVIEW" || true)
  else REVIEW_COUNT=0; fi
  echo "review_file: $TODAYS_REVIEW"
  echo "review_time: $(date '+%Y-%m-%d %H:%M')"
  echo "review_count: $REVIEW_COUNT"

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
  exit 0
fi

# ==============
# PREFLIGHT
# ==============
# the shared scan sits beside this file, not beside the repo being scanned: resolve them before
# anything cds to a repo root, since BASH_SOURCE arrives relative and would follow that cd
SHARED=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../shared" 2>/dev/null && pwd || true)
if [ ! -f "$SHARED/secrets.sh" ]; then
  echo "fatal: no shared/secrets.sh reachable from this sidecar" >&2; exit 1; fi
# shellcheck source=../../shared/secrets.sh
. "$SHARED/secrets.sh"

# character counts, not byte counts: bash's ${#var} is multibyte-aware under a utf-8 locale, and
# every em dash in a verdict is 3 bytes — a byte count would flag lines legally under the cap
UTF8_LOCALE=$(locale -a 2>/dev/null | grep -iE '^(C|en_US)\.(utf-?8)$' | head -n 1 || true)
if [ -n "$UTF8_LOCALE" ]; then export LC_ALL="$UTF8_LOCALE"; fi

MAX_WIDTH=100
STRICT=0
KEEP=0
TEMPLATE="plugins/retardify/skills/review/SKILL.md"
ARTIFACTS=".operator/reviews"

# the subsections every scorecard carries, which is the one thing every entry must agree on
EXPECTED_SECTIONS=$'reality check\neffort vs output\nrisk & maintenance traps\ngrades'

# the three lanes, in order; the template exists so a strong infra grade cannot hide a weak test one
EXPECTED_LANES=$'infra/tooling\napp/features\ntests/reality'

# "where the time actually went, in one or two lines"
MAX_EFFORT_LINES=2

REVIEWS=()
for arg in "$@"; do
  case "$arg" in
    --strict) STRICT=1;;
    --keep) KEEP=1;;
    -h|--help) sed -n '2,11p' "$0"; exit 0;;
    -*) echo "fatal: unknown flag $arg" >&2; exit 1;;
    *) REVIEWS+=("$arg");;
  esac
done

# no paths given: scan the whole artifact directory, anchored to the repo root so the default
# works from any subdirectory — same posture as the @git* sidecars
if [ ${#REVIEWS[@]} -eq 0 ]; then
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "fatal: not a git repository, and no paths given" >&2; exit 1; fi
  cd "$(git rev-parse --show-toplevel)"
  if [ ! -d "$ARTIFACTS" ]; then echo "fatal: no $ARTIFACTS/ to scan" >&2; exit 1; fi
  REVIEWS=("$ARTIFACTS"/*.md)
fi

# a directory argument expands to the scorecard files inside it
EXPANDED=()
for path in "${REVIEWS[@]}"; do
  if [ -d "$path" ]; then
    for nested in "$path"/*.md; do [ -f "$nested" ] && EXPANDED+=("$nested"); done
  elif [ -f "$path" ]; then EXPANDED+=("$path")
  else echo "fatal: no such scorecard file: $path" >&2; exit 1; fi
done
REVIEWS=("${EXPANDED[@]}")

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

# emit "START<TAB>END<TAB>HEADING" per `## ` entry, so every check can scope itself to one scorecard
entries() {
  awk '
    /^## / { if (start) print start "\t" NR - 1 "\t" heading; start = NR; heading = substr($0, 4); next }
    END { if (start) print start "\t" NR "\t" heading }
  ' "$1"
}

# emit "LINENO<TAB>TEXT" for every line inside one entry's `### <name>` block; any heading closes
# it, so a malformed entry cannot bleed its body into the scorecard that follows
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
#   each takes a scorecard path and appends findings; to add one, write a function and list it below
# ==============

# "one review file per day" — the date in the name is what makes grade drift readable
check_filename() {
  local file=$1 base dir
  base=$(basename "$file")
  dir=$(dirname "$file")
  if ! printf '%s' "$base" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}\.md$'; then
    err "$file" 1 filename "one review file per day, named YYYY-MM-DD.md"
  fi
  case "$dir" in
    "$ARTIFACTS"|"./$ARTIFACTS"|*"/$ARTIFACTS") ;;
    *) warn "$file" 1 location "scorecard artifacts live in $ARTIFACTS/";;
  esac
}


# the agent opens the file with its own path as the h1, so a mismatch means the file was copied
# from another day — and grade drift across dates is unreadable once two days share a file
check_header() {
  local file=$1 expected actual
  expected="# $ARTIFACTS/$(basename "$file")"
  actual=$(sed -n '1p' "$file")
  if [ "$actual" != "$expected" ]; then
    err "$file" 1 header "line 1 must read '$expected'"
  fi
}

# "appended each run, many scorecards per file" — numbering and timestamps are the append order
check_entries() {
  local file=$1 start end heading number stamp expected=1 previous='' count=0 date
  date=$(basename "$file" .md)
  while IFS=$'\t' read -r start end heading; do
    count=$((count + 1))
    if ! printf '%s' "$heading" \
      | grep -qE '^Review #[0-9]+: [0-9]{4}-[0-9]{2}-[0-9]{2} ([01][0-9]|2[0-3]):[0-5][0-9]$'; then
      err "$file" "$start" entry_heading "entries read '## Review #N: YYYY-MM-DD HH:MM'"
      continue
    fi
    number=$(printf '%s' "$heading" | sed -n 's/^Review #\([0-9]\{1,\}\):.*/\1/p')
    stamp=$(printf '%s' "$heading" | sed -n 's/^Review #[0-9]\{1,\}: \(.*\)$/\1/p')
    if [ "$number" -ne "$expected" ]; then
      err "$file" "$start" entry_numbering "scorecard $number where $expected was expected"
    fi
    expected=$((number + 1))
    case "$stamp" in
      "$date "*) ;;
      *) err "$file" "$start" entry_date "timestamped $stamp in the file for $date";;
    esac
    if [ -n "$previous" ] && [[ "$stamp" < "$previous" ]]; then
      warn "$file" "$start" entry_order "timestamp precedes the scorecard above it; each run appends"
    fi
    previous=$stamp
  done < <(entries "$file")
  if [ "$count" -eq 0 ]; then
    warn "$file" 1 empty "seeded, holds no scorecards yet"
  fi
}

# the four subsections, in the template's order; a scorecard that stops before `grades` is an
# opinion, and reordering them breaks reading two days of scorecards side by side
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

# "each documented claim, followed by what the telemetry actually shows" — the colon is the join
# between the two halves, so a bullet without one is asserting a reality nobody can check
check_reality() {
  local file=$1 start end heading lineno text count
  while IFS=$'\t' read -r start end heading; do
    count=0
    while IFS=$'\t' read -r lineno text; do
      case "$text" in "- "*) ;; *) continue;; esac
      count=$((count + 1))
      if ! printf '%s' "$text" | grep -q ': '; then
        err "$file" "$lineno" reality_shape "read '- [claim from docs]: [harsh reality]'"
      fi
    done < <(subsection "$file" "$start" "$end" 'reality check')
    if [ "$count" -eq 0 ]; then
      err "$file" "$start" reality_empty "no claim-versus-telemetry pairs; that is the whole scorecard"
    fi
  done < <(entries "$file")
}

# "where the time actually went, in one or two lines" — a paragraph here is a play-by-play
check_effort() {
  local file=$1 start end heading count
  while IFS=$'\t' read -r start end heading; do
    count=$(subsection "$file" "$start" "$end" 'effort vs output' | cut -f2- \
      | grep -cv '^[[:space:]]*$' || true)
    if [ "$count" -eq 0 ]; then
      err "$file" "$start" effort_empty "name where the time actually went, in one or two lines"
    elif [ "$count" -gt "$MAX_EFFORT_LINES" ]; then
      warn "$file" "$start" effort_length "$count lines; the template allows $MAX_EFFORT_LINES"
    fi
  done < <(entries "$file")
}

# "name specific files, claims, and commits; an unfalsifiable criticism is worthless" — a `path`
# or a number is the falsifiable part, so a trap with neither cannot be acted on or disproved
check_traps() {
  local file=$1 start end heading lineno text count
  while IFS=$'\t' read -r start end heading; do
    count=0
    while IFS=$'\t' read -r lineno text; do
      # blank and whitespace-only lines are spacing, not traps
      case "$text" in *[![:space:]]*) ;; *) continue;; esac
      count=$((count + 1))
      if ! printf '%s' "$text" | grep -qE '`|[0-9]'; then
        warn "$file" "$lineno" unfalsifiable "name the file, claim or count; this cannot be disproved"
      fi
    done < <(subsection "$file" "$start" "$end" 'risk & maintenance traps')
    if [ "$count" -eq 0 ]; then
      err "$file" "$start" traps_empty "name the specific files, ignored rules or landmines"
    fi
  done < <(entries "$file")
}

# "`grades` are A-F per lane" and all three lanes are always reported, in the template's order,
# because dropping the weak lane is exactly how a scorecard gets softened
check_grades() {
  local file=$1 start end heading lineno text lane grade actual
  while IFS=$'\t' read -r start end heading; do
    actual=''
    while IFS=$'\t' read -r lineno text; do
      case "$text" in "- **"*) ;; *) continue;; esac
      if ! printf '%s' "$text" | grep -qE '^- \*\*[^*]+:\*\* [A-F][+-]?$'; then
        err "$file" "$lineno" grade_shape "lanes read '- **lane:** A-F', one grade, nothing else"
        continue
      fi
      lane=$(printf '%s' "$text" | sed -n 's/^- \*\*\([^*]*\):\*\*.*/\1/p')
      grade=$(printf '%s' "$text" | sed -n 's/^.*\*\* \([A-F][+-]\{0,1\}\)$/\1/p')
      actual="$actual$lane"$'\n'
      if [ "$grade" = 'E' ]; then
        warn "$file" "$lineno" grade_value "E is not a grade anybody hands out; D or F"
      fi
    done < <(subsection "$file" "$start" "$end" grades)
    actual=${actual%$'\n'}
    if [ "$actual" != "$EXPECTED_LANES" ]; then
      err "$file" "$start" grade_lanes "all three lanes, in order; got $(printf '%s' "$actual" | tr '\n' '>' | sed 's/>$//')"
    fi
  done < <(entries "$file")
}

# "**verdict:** one unapologetic sentence on the actual state of the codebase"
check_verdict() {
  local file=$1 start end heading lineno text body count sentence
  while IFS=$'\t' read -r start end heading; do
    count=0
    while IFS=$'\t' read -r lineno text; do
      case "$text" in "**verdict:**"*) ;; *) continue;; esac
      count=$((count + 1))
      body=$(printf '%s' "$text" | sed 's/^\*\*verdict:\*\*[[:space:]]*//')
      if [ -z "$body" ]; then
        err "$file" "$lineno" verdict_empty "the verdict is the one line anybody will remember"
      fi
      # one sentence: a terminator mid-line means a second sentence started
      sentence=$(printf '%s' "${body%.}" | grep -cE '[.!?] +[^[:space:]]' || true)
      if [ "$sentence" -ne 0 ]; then
        warn "$file" "$lineno" verdict_length "one sentence, unapologetic; this reads as several"
      fi
    done < <(subsection "$file" "$start" "$end" grades)
    if [ "$count" -eq 0 ]; then
      err "$file" "$start" verdict_missing "every scorecard ends on a **verdict:** line"
    elif [ "$count" -gt 1 ]; then
      err "$file" "$start" verdict_missing "$count verdict lines; a scorecard has exactly one"
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

# "skip the raw telemetry dump; keep the read of it, not the printout" — a fenced block in a
# scorecard is almost always that dump, and an unclosed fence swallows every entry after it
check_fences() {
  local file=$1 hit count=0
  while IFS= read -r hit; do
    if [ -z "$hit" ]; then continue; fi
    count=$((count + 1))
    if [ $((count % 2)) -eq 1 ]; then
      warn "$file" "${hit%%:*}" telemetry_dump "keep the read of the telemetry, not the printout"
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
      | grep -oE 'YYYY-MM-DD|HH:MM|A-F|\*example:\*|claim from docs|harsh reality|repeat the above format' \
      | head -n 1)
    err "$file" "${hit%%:*}" placeholder "template scaffolding survived: $token"
  done < <(grep -nE 'YYYY-MM-DD|HH:MM|A-F|\*example:\*|claim from docs|harsh reality|repeat the above format' "$file" || true)
}


# --- run list (add new checks here) ---
for review in "${REVIEWS[@]}"; do
  check_filename    "$review"
  check_header      "$review"
  check_entries     "$review"
  check_subsections "$review"
  check_reality     "$review"
  check_effort      "$review"
  check_traps       "$review"
  check_grades      "$review"
  check_verdict     "$review"
  check_width       "$review"
  check_fences      "$review"
  check_placeholders "$review"
  scan_secrets      "$review"
done

# ==============
# TELEMETRY
# ==============
ERRORS=$(grep -c '^ERROR|' "$FINDINGS" || true)
WARNINGS=$(grep -c '^WARN|' "$FINDINGS" || true)
SECRETS=$(grep -c '|secret|' "$FINDINGS" || true)

cat <<EOF

=== reviews.sh sidecar ===
template: $TEMPLATE
scanned: ${#REVIEWS[@]} scorecard file(s)
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
- scorecards capture the doc-versus-reality gap at a moment in time, and are never edited after
- never soften a written scorecard, and never re-grade an older one to match a newer mood
- strong infra grades cannot mask weak app or test ones; grade each lane on its own evidence
- every reality-check pair quotes a claim that is actually written down somewhere
- grade drift across dated files is the point; a lane stuck at D is the finding
- the verdict is unapologetic, and says what the codebase is rather than what it could be
- skip the raw telemetry dump; keep the read of it, not the printout
- a key that reached a commit is already leaked; rotate it before rewriting anything
========================
EOF

if [ "$ERRORS" -gt 0 ]; then exit 1; fi
if [ "$STRICT" -eq 1 ] && [ "$WARNINGS" -gt 0 ]; then exit 1; fi
exit 0

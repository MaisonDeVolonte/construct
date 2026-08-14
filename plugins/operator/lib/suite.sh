#!/bin/bash
# =====================================================
# @file suite.sh - the operator suite, run as one pass
# =====================================================
# @description
# PAIR
# - library for `/operator:setup --audit` — runs every lens and merges them into one report
# - it sits in lib/ because a skill folder holds its own doc and its own sidecar, and nothing else
# - safe anytime: read-only by contract, since every lens it runs is read-only by contract
# - the question it answers is coverage: whether every lens ran, and what each one came back with
# CONTRACT
# - it invokes, preserves and correlates; no lens verdict is ever recomputed here
# - each lens output is kept whole, so the merged report can be checked against the raw text
# - a lens that fails to complete is an ERROR, never a zero: silence is the fault it looks for
# - counts are read from the telemetry a lens prints; a lens that prints none reads as ungraded
# LENSES
# - `settings` files, `permissions` gate, `scripts` sub-commands, `credentials` masks, `issues` feed
# - every run is all five in that order, since the lenses build on each other as they read
# - no flag narrows it: one lens belongs to its own skill, under its own artifact
# RUN
# - the suite costs minutes, and `scripts` owns most of it by replaying every extracted command
# - each lens reports the seconds it spent, so a long stage reads as work rather than a hang
# - the doc appends one entry to the day's suite audit, never editing an earlier one
# @see plugins/operator/skills/setup/SKILL.md, plugins/operator/skills/setup/setup.sh, .construct/operator/setup/audit/

set -euo pipefail

# the doc is read only after this has already run, so help is refused here or not at all; the doc's
# own '## Help' section owns the output, which is why this prints a marker rather than a usage text
case " $* " in *" --help "*|*" -h "*) echo "help: requested"; exit 0;; esac

# priced and gated here for the same reason help is: the doc is read only once this has already run.
# the scripts lens owns almost all of it, so the estimate counts what that lens will replay
ESTIMATE_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo .)
ESTIMATE_SCALE=$({ find "$ESTIMATE_ROOT/plugins" -path '*/skills/*/*.sh' 2>/dev/null || true; } | wc -l | tr -d ' ')
echo "estimate: scales with the ${ESTIMATE_SCALE:-0} sidecars the scripts lens replays command by command"
case " $* " in *" --confirm "*) ;; *) echo "confirm: required"; exit 0;; esac

# ==============
# PREFLIGHT
# ==============
# the lenses sit one level over in skills/: resolve from this file before any cd, since BASH_SOURCE
# arrives relative and cwd holds no plugins/operator/ once installed from a marketplace
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)
SHARED=$(cd "$HERE/../shared" 2>/dev/null && pwd || true)
if [ ! -f "$SHARED/secrets.sh" ]; then
  echo "fatal: no shared/secrets.sh reachable from this sidecar" >&2; exit 1; fi
# shellcheck source=../../shared/secrets.sh
. "$SHARED/secrets.sh"

# fixed and complete: a lens flag here would run a sibling's sidecar under this skill's artifact,
# filing a narrower report than `/operator:<lens>` under a heading that claims the whole stack
LENSES=(settings permissions scripts credentials issues)
# help and confirm both exited above, so any flag still here is one this sidecar does not take; a
# lens name is the likely miss, and the sibling that owns it answers better than a usage dump
while [ $# -gt 0 ]; do
  case "$1" in
    --confirm) ;;
    *) echo "fatal: unknown flag $1; reach for /operator:${1#--} if it names a lens" >&2; exit 1;;
  esac
  shift
done

if ! command -v jq >/dev/null 2>&1; then echo "fatal: jq is required" >&2; exit 1; fi
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "fatal: not a git repository" >&2; exit 1; fi

cd "$(git rev-parse --show-toplevel)"
ROOT=$(pwd)

# repo-local scratch: the sandbox denies writes outside cwd, and macos mktemp ignores TMPDIR
TMPROOT="$ROOT/tmp"
mkdir -p "$TMPROOT"
FINDINGS=$(mktemp "$TMPROOT/suiteaudit-findings.XXXXXX")
SCRATCH=$(mktemp -d "$TMPROOT/suiteaudit-scratch.XXXXXX")
cleanup() { st=$?; if [ "$st" -eq 0 ]; then rm -rf "$FINDINGS" "$SCRATCH"; fi; }
trap cleanup EXIT

err()  { printf 'ERROR|%s|%s|%s\n' "$1" "$2" "$3" >> "$FINDINGS"; }
warn() { printf 'WARN|%s|%s|%s\n'  "$1" "$2" "$3" >> "$FINDINGS"; }
pass() { printf 'PASS|%s|%s|%s\n'  "$1" "$2" "$3" >> "$FINDINGS"; }

# ==============
# LENSES - invoke, preserve, never regrade
# ==============
# a lens is trusted for its own verdict and nothing else: this reads the counts it printed, and a
# lens that prints none reads as ungraded rather than clean
LENS_STATUS=()
LENS_SECONDS=()

count_of() {
  printf '%s' "$1" | sed -n "s/^$2: \([0-9]\{1,\}\)\$/\1/p" | head -n 1
}

run_lens() {
  local lens=$1 script output code started elapsed errors warnings
  script="$HERE/../skills/$lens/$lens.sh"
  if [ ! -f "$script" ]; then
    err suite "$lens" "no $lens.sh in skills/$lens, so this lens never ran"
    LENS_STATUS+=("$lens|missing|-|-")
    LENS_SECONDS+=("$lens|0")
    return
  fi

  started=$SECONDS
  set +e
  output=$(bash "$script" 2>&1)
  code=$?
  set -e
  elapsed=$((SECONDS - started))
  printf '%s\n' "$output" > "$SCRATCH/$lens.out"
  LENS_SECONDS+=("$lens|$elapsed")

  errors=$(count_of "$output" errors)
  warnings=$(count_of "$output" warnings)

  # no count in the output means the lens exited before its telemetry, so its verdict is unknown.
  # reporting that as zero is the fail-open this sidecar exists to refuse
  if [ -z "$errors" ]; then
    err suite "$lens" "exited $code in ${elapsed}s printing no error count, so it is ungraded"
    LENS_STATUS+=("$lens|ungraded|-|-")
    return
  fi

  warnings=${warnings:-0}
  LENS_STATUS+=("$lens|graded|$errors|$warnings")
  if [ "$errors" -gt 0 ]; then
    err "$lens" errors "$errors error(s) in ${elapsed}s; the detail is in this lens's block below"
  else
    pass "$lens" errors "0 errors in ${elapsed}s"
  fi
  if [ "$warnings" -gt 0 ]; then
    warn "$lens" warnings "$warnings warning(s); each one is a judgement call in the block below"
  fi
}

SUITE_START=$SECONDS
for lens in "${LENSES[@]}"; do run_lens "$lens"; done
SUITE_ELAPSED=$((SECONDS - SUITE_START))

# ==============
# ARTIFACT
#   the suite's own dated artifact, graded here so nothing outside this file decides its shape
#   it keeps a tree of its own, since the roadmap beside it grades by a different set of rules
# ==============
ARTIFACT_KIND="suite"
ARTIFACT_SECTIONS=$'state\nfindings\nresolutions\ntelemetry'
ARTIFACT_LABELS='(Settings|Permissions|Scripts|Credentials|Issues|Suite)/[A-Za-z ]+'
ARTIFACT_MAX_WIDTH=100

# this sidecar reports "category|scope|detail", so location folds into the scope field
artifact_err()  { err "$3" "$1:$2" "$4"; }
artifact_warn() { warn "$3" "$1:$2" "$4"; }

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
  local expected=1 previous='' count=0 found=0 fixed=0 lineno text infence=0 blocks=0

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
    # heading to the file, so a settings entry in the suite file is caught rather than merged
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
        artifact_err "$rel" "$lineno" finding_shape 'findings read "- **Lens/Label** — what is wrong, and on what"'
        continue
      fi
      label=$(printf '%s' "$text" | sed -n 's/^- \*\*\([^*]*\)\*\*.*/\1/p')
      # every finding names the lens it came from, since a merged report with unattributed
      # findings cannot be checked back against the block it was read out of
      if ! printf '%s' "$label" | grep -qE "^($ARTIFACT_LABELS)\$"; then
        artifact_warn "$rel" "$lineno" finding_label "'$label' is not <Lens>/<Label> for a lens this suite runs"
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
      artifact_err "$rel" "$start" telemetry "telemetry holds the raw lens output, never blank"
      continue
    fi

    # the suite always runs every lens, so a missing block means an entry claiming the whole stack
    # while holding less; that is an error rather than a note, since no flag can narrow this run
    blocks=$(printf '%s' "$body" | grep -c '^```' || true)
    if [ "$blocks" -lt 2 ]; then
      artifact_warn "$rel" "$start" telemetry "fence the raw output, so a reader can tell it from prose"
    fi
    for lens in "${LENSES[@]}"; do
      printf '%s' "$body" | grep -q "^#### $lens\$" && continue
      artifact_err "$rel" "$start" telemetry_lens "no '#### $lens' block; every entry holds all 5"
    done
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

check_artifact ".construct/operator/setup/audit"

# ==============
# TELEMETRY
# ==============
ERRORS=$(grep -c '^ERROR|' "$FINDINGS" 2>/dev/null || true)
WARNINGS=$(grep -c '^WARN|' "$FINDINGS" 2>/dev/null || true)
PASSES=$(grep -c '^PASS|' "$FINDINGS" 2>/dev/null || true)
ERRORS=${ERRORS:-0}
WARNINGS=${WARNINGS:-0}
PASSES=${PASSES:-0}

TODAYS_AUDIT=".construct/operator/setup/audit/$(date +%Y-%m-%d).md"
if [ -f "$ROOT/$TODAYS_AUDIT" ];
then AUDIT_COUNT=$(grep -c '^## Suite Audit #' "$ROOT/$TODAYS_AUDIT" || true)
else AUDIT_COUNT=0; fi
AUDIT_COUNT=${AUDIT_COUNT:-0}

cat <<EOF

=== suite.sh sidecar ===
audit_file: $TODAYS_AUDIT
audit_count: $AUDIT_COUNT
next_audit: $((AUDIT_COUNT + 1))
timestamp: $(date '+%Y-%m-%d %H:%M')
lenses: ${#LENSES[@]} run in ${SUITE_ELAPSED}s
passes: $PASSES
errors: $ERRORS
warnings: $WARNINGS
--- lenses ---
EOF

# the roll-up names every lens and how it ended, so a lens that never ran cannot read as a clean one
for row in "${LENS_STATUS[@]}"; do
  IFS='|' read -r lens state lens_errors lens_warnings <<< "$row"
  secs=0
  for timed in "${LENS_SECONDS[@]}"; do
    case "$timed" in "$lens|"*) secs=${timed#*|};; esac
  done
  printf '%-12s %-9s errors=%-4s warnings=%-4s %ss\n' \
    "$lens" "$state" "$lens_errors" "$lens_warnings" "$secs"
done

cat <<'EOF'
--- findings ---
EOF

sort -t'|' -k2,2 -k3,3 "$FINDINGS" \
  | awk -F'|' '{ printf "%-5s %-12s %-30s %s\n", $1, $2, $3, $4 }'

# each lens output whole, under a heading the artifact reuses: the merged findings above are only
# checkable against the text they were read out of
for lens in "${LENSES[@]}"; do
  [ -f "$SCRATCH/$lens.out" ] || continue
  printf '\n--- %s (verbatim) ---\n' "$lens"
  cat "$SCRATCH/$lens.out"
done

cat <<'EOF'

--- needs a human (rules no script can judge) ---
- an ungraded lens is the finding that outranks every count, since that lens answered nothing
- a lens verdict is that lens's to make; this suite never overrules one, it only collects them
- read a settings verbs error against the permissions allow list, since one makes the other live
- a scripts no-match is a gap in the corpus as often as a gap in the rules
- the suite proves today's stack; an upgrade can move the boundary with no file changing
================================
EOF

if [ "$ERRORS" -gt 0 ]; then exit 1; fi
exit 0

#!/bin/bash
# ==================================================
# @file study.sh - study template validator sidecar
# ==================================================
# @description
# - sidecar for `study.md` — asserts a study matches the template that documents it
# - one check per machine-checkable rule; every rule needing judgement prints as a human checklist
# - ERROR breaks a rule the template states outright; WARN names a smell the template tolerates
# - defaults to every file in `docs/study/`; pass files or a directory to scope it
# - `--strict` promotes warnings to errors; exits 1 on any error, 0 otherwise
# @see AGENTS.md, AGENTS/shared/secrets.sh, AGENTS/templates/study.md, AGENTS/templates/plans.sh, docs/study/

set -euo pipefail

# ==============
# PREFLIGHT
# ==============
# the shared checks sit beside this file, not beside the repo being scanned: resolve them before
# anything cds to a repo root, since BASH_SOURCE arrives relative and would follow that cd
SHARED=$(cd "$(dirname "${BASH_SOURCE[0]}")/../shared" 2>/dev/null && pwd || true)
if [ ! -f "$SHARED/secrets.sh" ]; then
  echo "fatal: no AGENTS/shared/secrets.sh beside this sidecar" >&2; exit 1; fi
# shellcheck source=../shared/secrets.sh
. "$SHARED/secrets.sh"

# character counts, not byte counts: bash's ${#var} is multibyte-aware under a utf-8 locale, and
# every arrow in a model line is 3 bytes — a byte count would flag lines that are legally under the cap
UTF8_LOCALE=$(locale -a 2>/dev/null | grep -iE '^(C|en_US)\.(utf-?8)$' | head -n 1 || true)
if [ -n "$UTF8_LOCALE" ]; then export LC_ALL="$UTF8_LOCALE"; fi

MAX_WIDTH=100
STRICT=0
TEMPLATE="AGENTS/templates/study.md"
ARTIFACTS="docs/study"

# the template's own section order, which is the one thing every study must agree on
EXPECTED_SECTIONS=$'Model\nPattern'

# "the one idea to walk away with, 1-3 lines, no more"
MAX_MODEL_LINES=3

# below this, a list is too short to have an order worth reading anything into
MIN_ORDERED_FILES=3

STUDIES=()
for arg in "$@"; do
  case "$arg" in
    --strict) STRICT=1;;
    -h|--help) sed -n '2,11p' "$0"; exit 0;;
    -*) echo "fatal: unknown flag $arg" >&2; exit 1;;
    *) STUDIES+=("$arg");;
  esac
done

# no paths given: scan the whole artifact directory, anchored to the repo root so the default
# works from any subdirectory — same posture as the @git* sidecars
if [ ${#STUDIES[@]} -eq 0 ]; then
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "fatal: not a git repository, and no paths given" >&2; exit 1; fi
  cd "$(git rev-parse --show-toplevel)"
  if [ ! -d "$ARTIFACTS" ]; then echo "fatal: no $ARTIFACTS/ to scan" >&2; exit 1; fi
  STUDIES=("$ARTIFACTS"/*.md)
fi

# a directory argument expands to the studies inside it
EXPANDED=()
for path in "${STUDIES[@]}"; do
  if [ -d "$path" ]; then
    for nested in "$path"/*.md; do [ -f "$nested" ] && EXPANDED+=("$nested"); done
  elif [ -f "$path" ]; then EXPANDED+=("$path")
  else echo "fatal: no such study: $path" >&2; exit 1; fi
done
STUDIES=("${EXPANDED[@]}")

# findings collect as "SEV|file|line|category|detail" — line is its own field so the report can
# sort numerically; joining it to the path first sorts 121 above 31. the run fails on ERROR only
FINDINGS=$(mktemp)
SCRATCH=$(mktemp -d)
trap 'rm -rf "$FINDINGS" "$SCRATCH"' EXIT

err()  { printf 'ERROR|%s|%s|%s|%s\n' "$1" "$2" "$3" "$4" >> "$FINDINGS"; }
warn() { printf 'WARN|%s|%s|%s|%s\n' "$1" "$2" "$3" "$4" >> "$FINDINGS"; }

# emit "LINENO<TAB>TEXT" for every line inside a "## <name>" section, stopping at the next "## "
section() {
  awk -v want="## $2" '
    $0 == want { inside = 1; next }
    /^## / { inside = 0 }
    inside { print NR "\t" $0 }
  ' "$1"
}

# emit "LINENO<TAB>TEXT" for the file list, which owns everything between the two-line header and
# the first section heading
filelist() {
  awk 'NR > 2 { if (/^## /) exit; print NR "\t" $0 }' "$1"
}

# ==============
# CHECKS
#   each takes a study path and appends findings; to add one, write a function and list it below
# ==============

# "one file per feature/workflow, `docs/study/`, named `<feature>.md` in kebab-case"
check_filename() {
  local file=$1 base dir
  base=$(basename "$file")
  dir=$(dirname "$file")
  if ! printf '%s' "$base" | grep -qE '^[a-z0-9]+(-[a-z0-9]+)*\.md$'; then
    err "$file" 1 filename "one study per feature, named <feature>.md in kebab-case"
  fi
  case "$dir" in
    "$ARTIFACTS"|"./$ARTIFACTS"|*"/$ARTIFACTS") ;;
    *) warn "$file" 1 location "studies live in $ARTIFACTS/";;
  esac
}

# "tracked in git"
check_tracked() {
  local file=$1
  if ! git ls-files --error-unmatch "$file" >/dev/null 2>&1; then
    warn "$file" 1 untracked "studies are tracked in git; this one is not committed yet"
  fi
}

# "# STUDY: Short Title" then "one line 'big idea' description of the topic"
check_header() {
  local file=$1 title summary blank
  title=$(sed -n '1p' "$file")
  summary=$(sed -n '2p' "$file")
  blank=$(sed -n '3p' "$file")
  case "$title" in
    "# STUDY: "*) ;;
    *) err "$file" 1 title "line 1 must read '# STUDY: <short title>'";;
  esac
  if [ -z "$summary" ] || [ "${summary:0:1}" = "#" ]; then
    err "$file" 2 summary "line 2 must be the one-line big idea of what is being studied"
  fi
  if [ -n "$blank" ]; then
    err "$file" 3 summary "line 3 must be blank; the big idea is one line and never wraps"
  fi
}

# "sections run in this order: model, pattern" — the file list sits above both, unheaded
check_sections() {
  local file=$1 actual
  actual=$(grep -E '^## ' "$file" | sed 's/^## //' || true)
  if [ "$actual" != "$EXPECTED_SECTIONS" ]; then
    err "$file" 1 section_order "got $(printf '%s' "$actual" | tr '\n' '>' | sed 's/>$//')"
  fi
}

# "one line per file: what it is, why it's in this spot, one clause max" — a checkbox, because a
# study is read once with something ticked off at each step
check_files() {
  local file=$1 lineno text count=0
  while IFS=$'\t' read -r lineno text; do
    case "$text" in *[![:space:]]*) ;; *) continue;; esac
    case "$text" in
      # a blockquote here is an annotation about the study, not one of the files it lists
      ">"*) continue;;
      "- [ ] "*|"- [x] "*) count=$((count + 1));;
      "- "*) err "$file" "$lineno" file_shape "file lines are checkboxes: '- [ ] \`path\` is ...'"
             count=$((count + 1))
             continue;;
      *) err "$file" "$lineno" wrapped_clause "one clause per file, and the line never wraps"
         continue;;
    esac
    if ! printf '%s' "$text" | grep -q '`'; then
      err "$file" "$lineno" file_unnamed "name the file in ticks, so the reader can open it"
    fi
  done < <(filelist "$file")
  if [ "$count" -eq 0 ]; then
    err "$file" 3 file_list "no files listed; the list in build order is the study"
  fi
}

# "lists files in ideal-build order, not alphabetical or touched-order" — an alphabetical list is
# the one order that proves nobody thought about the order
check_build_order() {
  local file=$1 count
  filelist "$file" | cut -f2- | sed -n 's/^- \[[ x]\] `\([^`]*\)`.*/\1/p' > "$SCRATCH/files"
  count=$(grep -c . "$SCRATCH/files" || true)
  if [ "$count" -lt "$MIN_ORDERED_FILES" ]; then return 0; fi
  if sort -c "$SCRATCH/files" 2>/dev/null; then
    warn "$file" 3 alphabetical "$count files in alphabetical order; build order is the point"
  fi
}

# "the one idea to walk away with, 1-3 lines, no more"
check_model() {
  local file=$1 count
  count=$(section "$file" Model | cut -f2- | grep -cv '^[[:space:]]*$' || true)
  if [ "$count" -eq 0 ]; then
    err "$file" 1 model_empty "state the one idea to walk away with"
  elif [ "$count" -gt "$MAX_MODEL_LINES" ]; then
    err "$file" "$(grep -n '^## Model' "$file" | head -n 1 | cut -d: -f1)" model_length \
      "$count lines; the model is $MAX_MODEL_LINES lines at most"
  fi
}

# "how to build the next similar thing, using this as the reference" — numbered, because it is a
# sequence somebody follows, and a gap in the numbers means a step was dropped
check_pattern() {
  local file=$1 lineno text number expected=1 count=0
  while IFS=$'\t' read -r lineno text; do
    number=$(printf '%s' "$text" | sed -n 's/^\([0-9]\{1,\}\)\. .*/\1/p')
    if [ -z "$number" ]; then continue; fi
    count=$((count + 1))
    if [ "$number" -ne "$expected" ]; then
      err "$file" "$lineno" pattern_numbering "step $number where $expected was expected"
    fi
    expected=$((number + 1))
  done < <(section "$file" Pattern)
  if [ "$count" -eq 0 ]; then
    err "$file" 1 pattern_empty "give the numbered steps for building the next one of these"
  fi
}

# "`lines` carry a single clause, capped at 100 characters, and never wrap"
check_width() {
  local file=$1 lineno=0 line
  while IFS= read -r line; do
    lineno=$((lineno + 1))
    if [ ${#line} -gt "$MAX_WIDTH" ]; then
      err "$file" "$lineno" width "${#line} chars; the cap is $MAX_WIDTH"
    fi
  done < "$file"
}

# a stray fence swallows the rest of the study when rendered, so it is never cosmetic
check_fences() {
  local file=$1 count
  count=$(grep -cE '^[[:space:]]*```' "$file" || true)
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
      | grep -oE 'Short Title|big idea. description|\*example:\*|one line per file' | head -n 1)
    err "$file" "${hit%%:*}" placeholder "template scaffolding survived: $token"
  done < <(grep -nE 'Short Title|big idea. description|\*example:\*|one line per file' "$file" || true)
}


# --- run list (add new checks here) ---
for study in "${STUDIES[@]}"; do
  check_filename     "$study"
  check_tracked      "$study"
  check_header       "$study"
  check_sections     "$study"
  check_files        "$study"
  check_build_order  "$study"
  check_model        "$study"
  check_pattern      "$study"
  check_width        "$study"
  check_fences       "$study"
  check_placeholders "$study"
  scan_secrets       "$study"
done

# ==============
# TELEMETRY
# ==============
ERRORS=$(grep -c '^ERROR|' "$FINDINGS" || true)
WARNINGS=$(grep -c '^WARN|' "$FINDINGS" || true)
SECRETS=$(grep -c '|secret|' "$FINDINGS" || true)

cat <<EOF

=== study.sh sidecar ===
template: $TEMPLATE
scanned: ${#STUDIES[@]} study file(s)
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
- files are listed in ideal-build order, never alphabetical and never the order they were touched
- written after the feature ships, to build a mental model rather than to document a reference
- a map, not a textbook: every line earns its place, and nothing is here for completeness
- each file line says what it is and why it sits in that spot, in one clause
- the model is the single idea worth walking away with, even if the rest is forgotten
- the pattern is how to build the next one of these, using this feature as the reference
- a key that reached a commit is already leaked; rotate it before rewriting anything
========================
EOF

if [ "$ERRORS" -gt 0 ]; then exit 1; fi
if [ "$STRICT" -eq 1 ] && [ "$WARNINGS" -gt 0 ]; then exit 1; fi
exit 0

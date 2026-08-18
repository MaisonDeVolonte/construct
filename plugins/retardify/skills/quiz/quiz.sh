#!/bin/bash
# =============================================================================
# @file quiz.sh - study quiz sidecar: names the target, then grades what landed
# =============================================================================
# @description
# PAIR
# - the only sidecar for `/retardify:quiz`, which owns both halves of its own artifact
# - the doc carries the shape; this file names where it lands and grades what landed there
# - one skill is one SKILL.md and one sidecar, so nothing outside this pair decides its shape
# STATE
# - `absent` is a fresh sitting, `ungraded` waits on a grade, `graded` is closed evidence
# - the doc branches on that word, since generating and grading are two different runs
# - generation writes NO answer, so a verdict line on an ungraded quiz is a leak and an error
# RUN
# - no flag runs the trigger half, so every existing invocation is unchanged
# - `--check [paths]` runs the validator half; with no paths it grades the whole artifact dir
# - ERROR breaks a rule the doc states outright; WARN names a smell the doc tolerates
# @see plugins/retardify/skills/quiz/SKILL.md, .construct/retardify/quiz/, plugins/retardify/skills/guide/SKILL.md, plugins/retardify/shared/secrets.sh

set -euo pipefail

# the doc is read only after this has already run, so help is refused here or not at all; the doc's
# own '## Help' section owns the output, which is why this prints a marker rather than a usage text
case " $* " in *" --help "*|*" -h "*) echo "help: requested"; exit 0;; esac

# the smoke case proves this file parses and its guards return; /test-skills reads the sources,
# the @see paths and the tool guards statically, so nothing here runs a step of the skill
case " $* " in *" --test "*) echo "test: ok"; exit 0;; esac

# `--check` selects the validator half; anything else is the trigger, so the doc's own
# bang-injected call keeps working untouched
if [ "${1:-}" = "--check" ]; then
  shift
else
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "fatal: not a git repository" >&2; exit 1; fi
  cd "$(git rev-parse --show-toplevel)"

  ARTIFACTS=".construct/retardify/quiz"
  TEMPLATE="plugins/retardify/skills/quiz/SKILL.md"
  VALIDATOR="plugins/retardify/skills/quiz/quiz.sh --check"
  TODAY=$(date +%Y-%m-%d)

  FEATURE="$*"
  if [ -z "$FEATURE" ]; then
    echo "fatal: /retardify:quiz needs a feature, as in: /retardify:quiz the settings audit" >&2
    exit 1
  fi

  # the validator accepts lowercase letters, digits and hyphens only, so everything else collapses;
  # the date leads the name, so retaking the same feature later lands beside the first sitting
  SLUG=$(printf '%s' "$FEATURE" | tr '[:upper:]' '[:lower:]' \
    | sed -e 's/[^a-z0-9]/-/g' -e 's/--*/-/g' -e 's/^-//' -e 's/-$//' | cut -c1-60)
  SLUG=${SLUG%-}
  if [ -z "$SLUG" ]; then
    echo "fatal: the feature has no letters or digits to build a filename from" >&2; exit 1; fi

  mkdir -p "$ARTIFACTS"
  TARGET="$ARTIFACTS/$TODAY-$SLUG.md"

  # the three states the doc branches on: a fresh sitting writes questions, a taken one gets
  # graded, and a closed one is never rewritten, since a score is evidence of a moment
  if [ ! -e "$TARGET" ]; then STATE=absent
  elif grep -q '^- graded:' "$TARGET"; then STATE=graded
  else STATE=ungraded; fi

  TAKEN=0
  if [ -f "$TARGET" ]; then
    TAKEN=$(grep -c '^- \[x\] [A-D]\. ' "$TARGET" || true); fi
  EXISTING=$(find "$ARTIFACTS" -maxdepth 1 -type f -name '*.md' | wc -l | tr -d ' ')

  echo "=== /retardify:quiz telemetry ==="
  echo "feature: $FEATURE"
  echo "slug: $SLUG"
  echo "target: $TARGET"
  echo "state: $STATE"
  echo "picks_marked: $TAKEN"
  echo "questions: 20"
  echo "existing_quizzes: $EXISTING"
  echo "template: $TEMPLATE"
  echo "validator: $VALIDATOR"

  echo "--- quizzes already written ---"
  find "$ARTIFACTS" -maxdepth 1 -type f -name '*.md' | sort | head -10 || true

  case "$STATE" in
    ungraded)
      echo "--- grade it ---"
      echo "$TAKEN pick(s) marked; skip to the grading step rather than writing a new quiz";;
    graded)
      echo "--- ask first ---"
      echo "$TARGET is already scored; a graded quiz is evidence and is never rewritten";;
  esac
  echo "================================"
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
# every arrow and check mark in a quiz is 3 bytes — a byte count would flag legal lines
UTF8_LOCALE=$(locale -a 2>/dev/null | grep -iE '^(C|en_US)\.(utf-?8)$' | head -n 1 || true)
if [ -n "$UTF8_LOCALE" ]; then export LC_ALL="$UTF8_LOCALE"; fi

MAX_WIDTH=100
STRICT=0
KEEP=0
TEMPLATE="plugins/retardify/skills/quiz/SKILL.md"
ARTIFACTS=".construct/retardify/quiz"

# the template's own section order, which is the one thing every quiz must agree on
EXPECTED_SECTIONS=$'Files\nModel\nPattern\nQuiz'

# "the one idea to walk away with, 1-3 lines, no more"
MAX_MODEL_LINES=3

# below this, a list is too short to have an order worth reading anything into
MIN_ORDERED_FILES=3

# the sitting the shape describes; fewer is allowed and reported, since a short quiz still grades
EXPECTED_QUESTIONS=20

# every question offers exactly these, in this order, so a pick is unambiguous to read back
OPTION_LABELS='A B C D'

QUIZZES=()
for arg in "$@"; do
  case "$arg" in
    --strict) STRICT=1;;
    --keep) KEEP=1;;
    -*) echo "fatal: unknown flag $arg" >&2; exit 1;;
    *) QUIZZES+=("$arg");;
  esac
done

# no paths given: scan the whole artifact directory, anchored to the repo root so the default
# works from any subdirectory — same posture as the plan and manual sidecars
if [ ${#QUIZZES[@]} -eq 0 ]; then
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "fatal: not a git repository, and no paths given" >&2; exit 1; fi
  cd "$(git rev-parse --show-toplevel)"
  if [ ! -d "$ARTIFACTS" ]; then echo "fatal: no $ARTIFACTS/ to scan" >&2; exit 1; fi
  QUIZZES=("$ARTIFACTS"/*.md)
fi

# a directory argument expands to the quizzes inside it
EXPANDED=()
for path in "${QUIZZES[@]}"; do
  if [ -d "$path" ]; then
    for nested in "$path"/*.md; do [ -f "$nested" ] && EXPANDED+=("$nested"); done
  elif [ -f "$path" ]; then EXPANDED+=("$path")
  else echo "fatal: no such quiz: $path" >&2; exit 1; fi
done
QUIZZES=("${EXPANDED[@]}")

# repo-local scratch: the sandbox denies writes outside cwd, and macos mktemp ignores TMPDIR
TMPROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)/tmp"
TMPTAG=$(basename "${BASH_SOURCE[0]}" .sh)
mkdir -p "$TMPROOT"

# findings collect as "SEV|file|line|category|detail" — line is its own field so the report can
# sort numerically; joining it to the path first sorts 121 above 31. the run fails on ERROR only
FINDINGS=$(mktemp "$TMPROOT/$TMPTAG-findings.XXXXXX")
SCRATCH=$(mktemp -d "$TMPROOT/$TMPTAG-scratch.XXXXXX")
# a failed run leaves scratch behind to read; --keep does the same after a clean one
cleanup() { st=$?; if [ "$KEEP" -eq 0 ] && [ "$st" -eq 0 ]; then rm -rf "$FINDINGS" "$SCRATCH"; fi; }
trap cleanup EXIT

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

# a graded quiz carries the verdicts; an ungraded one is the same file before anything was scored
is_graded() { grep -q '^- graded:' "$1"; }

# ==============
# CHECKS
#   each takes a quiz path and appends findings; to add one, write a function and list it below
# ==============

# "`.construct/retardify/quiz/YYYY-MM-DD-<feature>.md`, kebab-case, one per sitting"
check_filename() {
  local file=$1 base dir
  base=$(basename "$file")
  dir=$(dirname "$file")
  if ! printf '%s' "$base" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}-[a-z0-9]+(-[a-z0-9]+)*\.md$'; then
    err "$file" 1 filename "expected YYYY-MM-DD-<feature>.md in kebab-case"
  fi
  case "$dir" in
    "$ARTIFACTS"|"./$ARTIFACTS"|*"/$ARTIFACTS") ;;
    *) warn "$file" 1 location "quizzes live in $ARTIFACTS/";;
  esac
}

# "# QUIZ: Short Title" then "one line 'big idea' description of the topic"
check_header() {
  local file=$1 title summary blank
  title=$(sed -n '1p' "$file")
  summary=$(sed -n '2p' "$file")
  blank=$(sed -n '3p' "$file")
  case "$title" in
    "# QUIZ: "*) ;;
    *) err "$file" 1 title "line 1 must read '# QUIZ: <short title>'";;
  esac
  if [ -z "$summary" ] || [ "${summary:0:1}" = "#" ]; then
    err "$file" 2 summary "line 2 must be the one-line big idea of what the quiz covers"
  fi
  if [ -n "$blank" ]; then
    err "$file" 3 summary "line 3 must be blank; the big idea is one line and never wraps"
  fi
}

# the four sections in the order the shape states them
check_sections() {
  local file=$1 actual
  actual=$(grep -E '^## ' "$file" | sed 's/^## //' || true)
  if [ "$actual" != "$EXPECTED_SECTIONS" ]; then
    err "$file" 1 section_order "got $(printf '%s' "$actual" | tr '\n' '>' | sed 's/>$//')"
  fi
}

# one line per file saying what it is and why it sits in that spot
# a checkbox, since the study half is read once with something ticked off at each step
check_files() {
  local file=$1 lineno text count=0
  while IFS=$'\t' read -r lineno text; do
    case "$text" in *[![:space:]]*) ;; *) continue;; esac
    case "$text" in
      # a blockquote here is an annotation about the quiz, not one of the files it lists
      ">"*) continue;;
      "- [ ] "*|"- [x] "*) count=$((count + 1));;
      "- "*) err "$file" "$lineno" file_shape "file lines are checkboxes: '- [x] \`path\` is ...'"
             count=$((count + 1))
             continue;;
      *) err "$file" "$lineno" wrapped_clause "one clause per file, and the line never wraps"
         continue;;
    esac
    if ! printf '%s' "$text" | grep -q '`'; then
      err "$file" "$lineno" file_unnamed "name the file in ticks, so the reader can open it"
    fi
  done < <(section "$file" Files)
  if [ "$count" -eq 0 ]; then
    err "$file" 3 file_list "no files listed; the list in build order is the study half"
  fi
}

# "lists files in ideal-build order, not alphabetical or touched-order" — an alphabetical list is
# the one order that proves nobody thought about the order
check_build_order() {
  local file=$1 count
  section "$file" Files | cut -f2- | sed -n 's/^- \[[ x]\] `\([^`]*\)`.*/\1/p' > "$SCRATCH/files"
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

# one question's worth of accounting, run when the next question starts and once at the end
# a verdict before the grade is the leak this whole skill exists to prevent, so it errors
flush_question() {
  local file=$1 num=$2 line=$3 opts=$4 labels=$5 marks=$6 verdicts=$7 graded=$8
  [ -n "$num" ] || return 0
  if [ "$opts" -ne 4 ]; then
    err "$file" "$line" option_count "Q$num offers $opts options; every question offers four"
  elif [ "$labels" != "$OPTION_LABELS" ]; then
    err "$file" "$line" option_labels "Q$num labels its options '$labels'; expected $OPTION_LABELS"
  fi
  if [ "$graded" -eq 0 ]; then
    if [ "$verdicts" -ne 0 ]; then
      err "$file" "$line" answer_leak "Q$num carries a verdict before the quiz was graded"
    fi
    if [ "$marks" -gt 1 ]; then
      err "$file" "$line" multi_pick "Q$num has $marks options marked; a pick is one answer"
    fi
  else
    if [ "$verdicts" -ne 1 ]; then
      err "$file" "$line" no_verdict "Q$num carries $verdicts verdict lines; a graded question has one"
    fi
    if [ "$marks" -lt 1 ] || [ "$marks" -gt 2 ]; then
      err "$file" "$line" graded_marks "Q$num marks $marks options; a grade marks the pick and the answer"
    fi
  fi
}

# the quiz half: numbering, the four options, and whether any answer leaked before grading
check_quiz() {
  local file=$1 lineno text graded=0 num='' line=0 opts=0 labels='' marks=0 verdicts=0
  local expected=1 total=0 opt
  is_graded "$file" && graded=1

  if ! grep -q '^- generated:' "$file"; then
    err "$file" 1 no_generated "the quiz block opens with a '- generated:' timestamp"
  fi

  while IFS=$'\t' read -r lineno text; do
    case "$text" in
      '**Q'*)
        flush_question "$file" "$num" "$line" "$opts" "${labels# }" "$marks" "$verdicts" "$graded"
        num=$(printf '%s' "$text" | sed -n 's/^\*\*Q\([0-9]\{1,\}\).*/\1/p')
        if [ -z "$num" ]; then continue; fi
        total=$((total + 1))
        line=$lineno
        opts=0; labels=''; marks=0; verdicts=0
        if [ "$num" -ne "$expected" ]; then
          err "$file" "$lineno" question_order "Q$num where Q$expected was expected"
        fi
        expected=$((num + 1))
        continue;;
      "> ✓"*|"> ✗"*) verdicts=$((verdicts + 1)); continue;;
    esac
    opt=$(printf '%s' "$text" | sed -n 's/^- \[[ x]\] \([A-D]\)\. .*/\1/p')
    if [ -n "$opt" ]; then
      opts=$((opts + 1))
      labels="$labels $opt"
      case "$text" in "- [x] "*) marks=$((marks + 1));; esac
    fi
  done < <(section "$file" Quiz)
  flush_question "$file" "$num" "$line" "$opts" "${labels# }" "$marks" "$verdicts" "$graded"

  if [ "$total" -eq 0 ]; then
    err "$file" 1 quiz_empty "no questions; the quiz is the point of the artifact"
  elif [ "$total" -ne "$EXPECTED_QUESTIONS" ]; then
    warn "$file" 1 question_count "$total questions; the shape describes $EXPECTED_QUESTIONS"
  fi

  # a score nobody can check against the questions is a number rather than a result
  if [ "$graded" -eq 1 ] && ! grep -qE '^- graded:.*score [0-9]+/[0-9]+' "$file"; then
    err "$file" "$(grep -n '^- graded:' "$file" | head -n 1 | cut -d: -f1)" no_score \
      "a graded quiz states 'score N/M' on its graded line"
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

# a stray fence swallows the rest of the quiz when rendered, so it is never cosmetic
check_fences() {
  local file=$1 count
  count=$(grep -cE '^[[:space:]]*```' "$file" || true)
  if [ $((count % 2)) -ne 0 ]; then
    err "$file" 1 fences "$count fence markers; one is unclosed"
  fi
}

# scaffolding left in a shipped artifact reads as fact to everyone downstream
check_placeholders() {
  local file=$1 hit token pattern
  pattern='Short Title|big idea. description|\*example:\*|one line per file|YYYY-MM-DD HH:MM'
  while IFS= read -r hit; do
    if [ -z "$hit" ]; then continue; fi
    token=$(printf '%s' "${hit#*:}" | grep -oE "$pattern" | head -n 1)
    err "$file" "${hit%%:*}" placeholder "template scaffolding survived: $token"
  done < <(grep -nE "$pattern" "$file" || true)
}

# --- run list (add new checks here) ---
for quiz in "${QUIZZES[@]}"; do
  check_filename     "$quiz"
  check_header       "$quiz"
  check_sections     "$quiz"
  check_files        "$quiz"
  check_build_order  "$quiz"
  check_model        "$quiz"
  check_pattern      "$quiz"
  check_quiz         "$quiz"
  check_width        "$quiz"
  check_fences       "$quiz"
  check_placeholders "$quiz"
  scan_secrets       "$quiz"
done

# ==============
# TELEMETRY
# ==============
ERRORS=$(grep -c '^ERROR|' "$FINDINGS" || true)
WARNINGS=$(grep -c '^WARN|' "$FINDINGS" || true)
SECRETS=$(grep -c '|secret|' "$FINDINGS" || true)
LEAKS=$(grep -c '|answer_leak|' "$FINDINGS" || true)

cat <<EOF

=== quiz.sh sidecar ===
template: $TEMPLATE
scanned: ${#QUIZZES[@]} quiz file(s)
width_cap: $MAX_WIDTH chars
answer_leaks: $LEAKS
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
- written after the feature ships, to test the mental model rather than to document a reference
- every question tests a why, a tradeoff or an order of operations, never trivia recall
- no question is answerable from the study half above it; a quiz that quotes itself teaches nothing
- the three wrong options are each plausible, since an obvious decoy tests nothing
- a grade names the mechanism behind the right answer, not just the letter
- every miss carries the transferable concept underneath it, which is the actual deliverable
- a key that reached a commit is already leaked; rotate it before rewriting anything
========================
EOF

if [ "$ERRORS" -gt 0 ]; then exit 1; fi
if [ "$STRICT" -eq 1 ] && [ "$WARNINGS" -gt 0 ]; then exit 1; fi
exit 0

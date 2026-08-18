#!/bin/bash
# =====================================================================================
# @file research.sh - research brief sidecar: names the target, then grades what landed
# =====================================================================================
# @description
# PAIR
# - the only sidecar for `/retardify:research`, which owns both halves of its own artifact
# - the doc carries the shape; this file names where it lands and grades what landed there
# - one skill is one SKILL.md and one sidecar, so nothing outside this pair decides its shape
# RUN
# - no flag runs the trigger half, so the doc's bang-injected call reaches it unchanged
# - `--check [paths]` runs the validator half; with no paths it grades the whole artifact dir
# - ERROR breaks a rule the doc states outright; WARN names a smell the doc tolerates
# REACH
# - the trigger half reports the sandbox network allowlist, since bash egress is what fails first
# - a fanned agent reads that list to learn whether curl can reach a docs host at all
# - an unlisted host means fetching through the harness tools instead of through bash
# @see plugins/retardify/skills/research/SKILL.md, .construct/retardify/research/, plugins/retardify/skills/graph/SKILL.md, plugins/retardify/shared/secrets.sh

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

  ARTIFACTS=".construct/retardify/research"
  TEMPLATE="plugins/retardify/skills/research/SKILL.md"
  VALIDATOR="plugins/retardify/skills/research/research.sh --check"
  TODAY=$(date +%Y-%m-%d)

  QUESTION="$*"
  if [ -z "$QUESTION" ]; then
    echo "fatal: /retardify:research needs a question, as in: /retardify:research do rulesets replace permission rules" >&2
    exit 1
  fi

  # the validator accepts letters digits and hyphens only, so all else collapses to a hyphen
  SLUG=$(printf '%s' "$QUESTION" | tr '[:upper:]' '[:lower:]' \
    | sed -e 's/[^a-z0-9]/-/g' -e 's/--*/-/g' -e 's/^-//' -e 's/-$//' | cut -c1-48)
  SLUG=${SLUG%-}
  if [ -z "$SLUG" ]; then
    echo "fatal: the question has no letters or digits to build a filename from" >&2; exit 1; fi

  mkdir -p "$ARTIFACTS"
  TARGET="$ARTIFACTS/$TODAY-$SLUG.md"
  if [ -e "$TARGET" ]; then COLLISION=yes; else COLLISION=no; fi
  EXISTING=$(find "$ARTIFACTS" -maxdepth 1 -type f -name '*.md' | wc -l | tr -d ' ')

  # the egress surface a fanned agent is about to hit: an unlisted host fails in bash before the
  # agent can read why, so the list is reported up front rather than discovered one curl at a time
  DOMAINS="unreadable"
  if command -v jq >/dev/null 2>&1 && [ -f .claude/settings.json ]; then
    DOMAINS=$(jq -r '(.sandbox.network.allowedDomains // []) | if length == 0 then "none listed"
      else join(", ") end' .claude/settings.json 2>/dev/null || echo "unreadable")
  fi

  echo "=== /retardify:research telemetry ==="
  echo "question: $QUESTION"
  echo "slug: $SLUG"
  echo "target: $TARGET"
  echo "collision: $COLLISION"
  echo "existing_briefs: $EXISTING"
  echo "sandbox_domains: $DOMAINS"
  echo "template: $TEMPLATE"
  echo "validator: $VALIDATOR"

  echo "--- most recent ---"
  find "$ARTIFACTS" -maxdepth 1 -type f -name '*.md' | sort -r | head -3 || true

  if [ "$COLLISION" = yes ]; then
    echo "--- stop ---"
    echo "a brief already holds this slug; sharpen the question or open the existing file"
  fi
  echo "====================================="
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

# character counts, not byte counts: bash's ${#var} is multibyte-aware under a utf-8 locale, and a
# brief quoting a doc carries multibyte punctuation a byte count would flag as an over-wide line
UTF8_LOCALE=$(locale -a 2>/dev/null | grep -iE '^(C|en_US)\.(utf-?8)$' | head -n 1 || true)
if [ -n "$UTF8_LOCALE" ]; then export LC_ALL="$UTF8_LOCALE"; fi

MAX_WIDTH=100
STRICT=0
KEEP=0
TEMPLATE="plugins/retardify/skills/research/SKILL.md"
ARTIFACTS=".construct/retardify/research"

# the template's own section order, which is the one thing every brief must agree on
EXPECTED_SECTIONS=$'VERDICT\nPROBED\nFINDINGS\nRECONCILED\nGAPS\nPLAN\nSOURCES'

# the four tiers a source is graded into; the tier is what separates a vendor's own claim about
# its product from a practitioner reporting what that product did to them
TIERS='official|vendor|industry|community'

# the three verdicts a reconciled row can carry, which is what makes the table a decision
VERDICTS='agrees|conflicts|untested'

BRIEFS=()
for arg in "$@"; do
  case "$arg" in
    --strict) STRICT=1;;
    --keep) KEEP=1;;
    -*) echo "fatal: unknown flag $arg" >&2; exit 1;;
    *) BRIEFS+=("$arg");;
  esac
done

# no paths given: scan the whole artifact directory, anchored to the repo root so the default
# works from any subdirectory — same posture as every sibling sidecar
if [ ${#BRIEFS[@]} -eq 0 ]; then
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "fatal: not a git repository, and no paths given" >&2; exit 1; fi
  cd "$(git rev-parse --show-toplevel)"
  if [ ! -d "$ARTIFACTS" ]; then echo "fatal: no $ARTIFACTS/ to scan" >&2; exit 1; fi
  BRIEFS=("$ARTIFACTS"/*.md)
fi

# a directory argument expands to the briefs inside it
EXPANDED=()
for path in "${BRIEFS[@]}"; do
  if [ -d "$path" ]; then
    for nested in "$path"/*.md; do [ -f "$nested" ] && EXPANDED+=("$nested"); done
  elif [ -f "$path" ]; then EXPANDED+=("$path")
  else echo "fatal: no such brief: $path" >&2; exit 1; fi
done
BRIEFS=("${EXPANDED[@]}")

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

# emit "LINENO<TAB>TEXT" for every line inside a '## ' section, its own heading excluded, stopping
# at the next '## '. a fenced '## ' cannot occur here, since the shape puts no headings in fences
section() {
  awk -v want="$2" '
    $0 == "## " want { inside = 1; next }
    /^## / { inside = 0 }
    inside { print NR "\t" $0 }
  ' "$1"
}

# ==============
# CHECKS
#   each takes a brief path and appends findings; to add one, write a function and list it below
# ==============

# "one file per brief, `.construct/retardify/research/`, named `YYYY-MM-DD-<title>.md`"
check_filename() {
  local file=$1 base dir
  base=$(basename "$file")
  dir=$(dirname "$file")
  if ! printf '%s' "$base" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}-[A-Za-z0-9-]+\.md$'; then
    err "$file" 1 filename "expected YYYY-MM-DD-<title>.md"
  fi
  case "$dir" in
    "$ARTIFACTS"|"./$ARTIFACTS"|*"/$ARTIFACTS") ;;
    *) warn "$file" 1 location "one brief per file, all of them in $ARTIFACTS/";;
  esac
}

# every brief opens on its own question, so a reader knows what was asked before what was found
check_title() {
  local file=$1 first second
  first=$(sed -n '1p' "$file")
  case "$first" in
    "# RESEARCH: "?*) ;;
    *) err "$file" 1 title "line 1 must read '# RESEARCH: <the question>'";;
  esac
  # the stamp is what dates the answer; a source moves and a brief carrying no date cannot be aged
  second=$(sed -n '2p' "$file")
  if ! printf '%s' "$second" | grep -qE '^> researched [0-9]{4}-[0-9]{2}-[0-9]{2} \|'; then
    err "$file" 2 stamp "line 2 must read '> researched YYYY-MM-DD | <counts>'"
  fi
}

# "sections run in the order the template prints them", listed in EXPECTED_SECTIONS above
# the answer sits above its evidence, so a reader can stop at any depth and still be correct
check_sections() {
  local file=$1 actual duplicate
  actual=$(grep -E '^## ' "$file" | sed 's/^## //' || true)
  if [ "$actual" != "$EXPECTED_SECTIONS" ]; then
    err "$file" 1 section_order "got $(printf '%s' "$actual" | tr '\n' '>' | sed 's/>$//')"
  fi
  duplicate=$(printf '%s' "$actual" | sort | uniq -d | tr '\n' ' ' || true)
  if [ -n "$duplicate" ]; then
    err "$file" 1 section_repeat "each section appears once; repeated: $duplicate"
  fi
}

# "lines carry a single clause and never wrap", capped at 100 characters
# a url is exempt since breaking one makes it unclickable; a table row is scanned by column
check_width() {
  local file=$1 lineno=0 line fence=0
  while IFS= read -r line; do
    lineno=$((lineno + 1))
    case "$line" in '```'*) fence=$((1 - fence)); continue;; esac
    if [ "$fence" -eq 1 ]; then continue; fi
    case "$line" in
      '|'*) continue;;
      *http*) continue;;
    esac
    if [ ${#line} -gt "$MAX_WIDTH" ]; then
      err "$file" "$lineno" width "${#line} chars; the cap is $MAX_WIDTH"
    fi
  done < "$file"
}

# a brief still carrying the template's own instructions was copied, not researched. these stems
# are the imperative openings of each section in the doc, and none survive a real answer
check_placeholders() {
  local file=$1 lineno text
  while IFS=: read -r lineno text; do
    if [ -z "$lineno" ]; then continue; fi
    err "$file" "$lineno" placeholder "template instruction left in place: ${text:0:40}"
  done < <(grep -nE '(the answer, before|a fact this run measured|a claim carrying its|what no source answered|verb first, runnable|one row per source)' "$file" || true)
}

# every source is numbered, carries a url, a tier and the date it was fetched; the date is what
# lets a later reader tell a current doc from one that moved after this brief was written
check_sources() {
  local file=$1 lineno text expected=1 number rows=0
  while IFS=$'\t' read -r lineno text; do
    case "$text" in
      [0-9]*". "*) ;;
      *) continue;;
    esac
    rows=$((rows + 1))
    number=$(printf '%s' "$text" | sed -n 's/^\([0-9]\{1,\}\)\. .*/\1/p')
    if [ "$number" -ne "$expected" ]; then
      err "$file" "$lineno" source_numbering "source $number where $expected was expected"
    fi
    expected=$((number + 1))
    if ! printf '%s' "$text" | grep -qE "^[0-9]+\. https?://[^[:space:]]+ \(($TIERS), fetched [0-9]{4}-[0-9]{2}-[0-9]{2}\)$"; then
      err "$file" "$lineno" source_shape "read '<n>. <url> (<tier>, fetched YYYY-MM-DD)'"
    fi
  done < <(section "$file" SOURCES)

  if [ "$rows" -eq 0 ]; then
    err "$file" 1 no_sources "a brief with no sources is a memory dump; fetch something or say so"
  fi
}

# "every claim carries its source as [n]" — an inline reference pointing past the end of the list
# is the fingerprint of a renumbered source list, and it silently recites the wrong url
check_citations() {
  local file=$1 lineno text ref highest=0 number cited
  cited="$SCRATCH/cited.txt"
  : > "$cited"

  while IFS=$'\t' read -r lineno text; do
    number=$(printf '%s' "$text" | sed -n 's/^\([0-9]\{1,\}\)\. .*/\1/p')
    if [ -n "$number" ] && [ "$number" -gt "$highest" ]; then highest=$number; fi
  done < <(section "$file" SOURCES)

  if [ "$highest" -eq 0 ]; then return 0; fi

  # the sources list numbers its own rows, so it is read for definitions and never for citations
  while IFS=$'\t' read -r lineno text; do
    for ref in $(printf '%s' "$text" | grep -oE '\[[0-9]+\]' | tr -d '[]'); do
      printf '%s\n' "$ref" >> "$cited"
      if [ "$ref" -lt 1 ] || [ "$ref" -gt "$highest" ]; then
        err "$file" "$lineno" citation "[$ref] resolves to nothing; the source list ends at $highest"
      fi
    done
  done < <(awk '$0 == "## SOURCES" { exit } { print NR "\t" $0 }' "$file")

  # a source nothing points at is either dead weight or a claim that lost its citation
  ref=1
  while [ "$ref" -le "$highest" ]; do
    if ! grep -qxF "$ref" "$cited"; then
      warn "$file" 1 uncited "source $ref is never cited; every source earns its place or goes"
    fi
    ref=$((ref + 1))
  done
}

# "reconciled is a table, and every row ends in a verdict" — a row without one is a comparison
# that was made and then not decided, which is the whole job of the section
check_reconciled() {
  local file=$1 lineno text rows=0 verdict
  while IFS=$'\t' read -r lineno text; do
    case "$text" in
      '|'*) ;;
      *) continue;;
    esac
    # the header and its separator are furniture, not rows
    case "$text" in
      *'---'*) continue;;
      '| claim |'*) continue;;
    esac
    rows=$((rows + 1))
    verdict=$(printf '%s' "$text" | awk -F'|' '{ gsub(/^[ \t]+|[ \t]+$/, "", $(NF-1)); print $(NF-1) }')
    if ! printf '%s' "$verdict" | grep -qE "^($VERDICTS)$"; then
      err "$file" "$lineno" verdict "last column reads '$verdict'; use one of $VERDICTS"
    fi
  done < <(section "$file" RECONCILED)

  if [ "$rows" -eq 0 ]; then
    err "$file" 1 no_reconciled "nothing was reconciled; the repo half of this brief never happened"
  fi
}

# "probed states what this repo does, measured this run" — an empty section means the brief is web
# reading with no local half, which is the failure this skill exists to prevent
check_probed() {
  local file=$1 rows
  rows=$(section "$file" PROBED | cut -f2- | grep -cE '^- ' || true)
  if [ "$rows" -eq 0 ]; then
    err "$file" 1 no_probes "probed is empty; a brief that never read this repo cannot reconcile"
  fi
}

# "gaps names what no source answered" — an empty gaps section claims total coverage, which is
# almost never true and is never checkable, so the honest form is a written `none`
check_gaps() {
  local file=$1 rows
  rows=$(section "$file" GAPS | cut -f2- | grep -cE '^- ' || true)
  if [ "$rows" -eq 0 ]; then
    err "$file" 1 no_gaps "gaps is empty; write '- none' and mean it, or name what stayed open"
  fi
}

# --- run list (add new checks here) ---
for brief in "${BRIEFS[@]}"; do
  check_filename     "$brief"
  check_title        "$brief"
  check_sections     "$brief"
  check_width        "$brief"
  check_placeholders "$brief"
  check_sources      "$brief"
  check_citations    "$brief"
  check_reconciled   "$brief"
  check_probed       "$brief"
  check_gaps         "$brief"
  scan_secrets       "$brief"
done

# ==============
# TELEMETRY
# ==============
ERRORS=$(grep -c '^ERROR|' "$FINDINGS" || true)
WARNINGS=$(grep -c '^WARN|' "$FINDINGS" || true)
SECRETS=$(grep -c '|secret|' "$FINDINGS" || true)

cat <<EOF

=== research.sh sidecar ===
template: $TEMPLATE
scanned: ${#BRIEFS[@]} brief(s)
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
- every source was actually fetched this run, never recalled from training
- a tier is graded honestly: a vendor describing its own product is never `industry`
- probed lines are measurements taken this run, not claims carried over from a previous brief
- reconciled rows compare the same thing on both sides, rather than two adjacent subjects
- a `conflicts` row says which side the brief believes, and why, somewhere in the plan
- gaps names what stayed open, and `none` was earned rather than typed
- the plan's steps are runnable by the reader, and each one names who runs it
- a key that reached a commit is already leaked; rotate it before rewriting anything
===========================
EOF

if [ "$ERRORS" -gt 0 ]; then exit 1; fi
if [ "$STRICT" -eq 1 ] && [ "$WARNINGS" -gt 0 ]; then exit 1; fi
exit 0

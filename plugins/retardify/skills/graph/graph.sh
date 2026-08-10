#!/bin/bash
# ================================================================================
# @file graph.sh - fan-out spec sidecar: names the target, then grades what landed
# ================================================================================
# @description
# PAIR
# - the only sidecar for `/retardify:graph`, which owns both halves of its own artifact
# - the doc carries the shape; this file names where it lands and grades what landed there
# - one skill is one SKILL.md and one sidecar, so nothing outside this pair decides its shape
# RUN
# - no flag runs the trigger half, so every existing invocation is unchanged
# - `--check [paths]` runs the validator half; with no paths it grades the whole artifact dir
# - ERROR breaks a rule the doc states outright; WARN names a smell the doc tolerates
# @see plugins/retardify/skills/graph/SKILL.md, .construct/retardify/graph/, plugins/retardify/skills/plan/SKILL.md, plugins/retardify/shared/secrets.sh

set -euo pipefail

# `--check` selects the validator half; anything else is the trigger, so the doc's own
# bang-injected call keeps working untouched
if [ "${1:-}" = "--check" ]; then
  shift
else
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "fatal: not a git repository" >&2; exit 1; fi
  cd "$(git rev-parse --show-toplevel)"

  ARTIFACTS=".construct/retardify/graph"
  TEMPLATE="plugins/retardify/skills/graph/SKILL.md"
  VALIDATOR="plugins/retardify/skills/graph/graph.sh --check"
  TODAY=$(date +%Y-%m-%d)

  GOAL="$*"
  if [ -z "$GOAL" ]; then
    echo "fatal: /write-graph needs a goal, as in: /write-graph import the backend repo" >&2; exit 1; fi

  # the validator accepts letters, digits and hyphens only, so all else collapses to a hyphen;
  # the length cap keeps a rambling goal from becoming a filename nobody can read back
  SLUG=$(printf '%s' "$GOAL" | tr '[:upper:]' '[:lower:]' \
    | sed -e 's/[^a-z0-9]/-/g' -e 's/--*/-/g' -e 's/^-//' -e 's/-$//' | cut -c1-60)
  SLUG=${SLUG%-}
  if [ -z "$SLUG" ]; then
    echo "fatal: the goal has no letters or digits to build a filename from" >&2; exit 1; fi

  mkdir -p "$ARTIFACTS"
  TARGET="$ARTIFACTS/$TODAY-operation-$SLUG.md"
  if [ -e "$TARGET" ]; then COLLISION=yes; else COLLISION=no; fi
  EXISTING=$(find "$ARTIFACTS" -maxdepth 1 -type f -name '*.md' | wc -l | tr -d ' ')

  echo "=== /write-graph telemetry ==="
  echo "goal: $GOAL"
  echo "slug: $SLUG"
  echo "target: $TARGET"
  echo "collision: $COLLISION"
  echo "existing_specs: $EXISTING"
  echo "template: $TEMPLATE"
  echo "validator: $VALIDATOR"

  echo "--- most recent ---"
  find "$ARTIFACTS" -maxdepth 1 -type f -name '*.md' | sort -r | head -3 || true

  if [ "$COLLISION" = yes ]; then
    echo "--- stop ---"
    echo "a spec already holds this slug; rename the goal or open the existing file"
  fi
  echo "=============================="
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
# the ▸ opening every spec is 3 bytes — a byte count would flag lines that are legally under the cap
UTF8_LOCALE=$(locale -a 2>/dev/null | grep -iE '^(C|en_US)\.(utf-?8)$' | head -n 1 || true)
if [ -n "$UTF8_LOCALE" ]; then export LC_ALL="$UTF8_LOCALE"; fi

MAX_WIDTH=100
STRICT=0
KEEP=0
TEMPLATE="plugins/retardify/skills/graph/SKILL.md"
ARTIFACTS=".construct/retardify/graph"

# the template's own field order, which is the one thing every spec must agree on
EXPECTED_FIELDS=$'GOAL\nCONTEXT\nDONE WHEN\nFAN OUT\nRULES\nVERIFY\nOUTPUT'

# the banner every spec opens with, so a spec is recognisable before it is parsed
BANNER='▸ GRAPH SPEC'

# every value starts here, keys in column 1: "DONE WHEN:" is the longest key at 10 characters,
# and the four spaces after it are what line the values up into a readable column
VALUE_COL=15

# "fan out names 2-5 agents"; below two there is nothing to merge, above five nothing converges
MIN_AGENTS=2
MAX_AGENTS=5

SPECS=()
for arg in "$@"; do
  case "$arg" in
    --strict) STRICT=1;;
    --keep) KEEP=1;;
    -h|--help) sed -n '2,11p' "$0"; exit 0;;
    -*) echo "fatal: unknown flag $arg" >&2; exit 1;;
    *) SPECS+=("$arg");;
  esac
done

# no paths given: scan the whole artifact directory, anchored to the repo root so the default
# works from any subdirectory — same posture as the @git* sidecars
if [ ${#SPECS[@]} -eq 0 ]; then
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "fatal: not a git repository, and no paths given" >&2; exit 1; fi
  cd "$(git rev-parse --show-toplevel)"
  if [ ! -d "$ARTIFACTS" ]; then echo "fatal: no $ARTIFACTS/ to scan" >&2; exit 1; fi
  SPECS=("$ARTIFACTS"/*.md)
fi

# a directory argument expands to the specs inside it
EXPANDED=()
for path in "${SPECS[@]}"; do
  if [ -d "$path" ]; then
    for nested in "$path"/*.md; do [ -f "$nested" ] && EXPANDED+=("$nested"); done
  elif [ -f "$path" ]; then EXPANDED+=("$path")
  else echo "fatal: no such spec: $path" >&2; exit 1; fi
done
SPECS=("${EXPANDED[@]}")

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

# emit "LINENO<TAB>TEXT" for every line of a field's value, the key line included, stopping at
# the next key. a field is a key in column 1; its continuations indent to the value column
field() {
  awk -v want="$2" -v col="$VALUE_COL" '
    $0 ~ "^" want ":" { inside = 1; print NR "\t" substr($0, col); next }
    /^[A-Z][A-Z ]*:/ { inside = 0 }
    inside && $0 != "" { print NR "\t" substr($0, col) }
  ' "$1"
}

# ==============
# CHECKS
#   each takes a spec path and appends findings; to add one, write a function and list it below
# ==============

# "one file per spec, `.construct/retardify/graph/`, named `YYYY-MM-DD-operation-<title>.md`"
check_filename() {
  local file=$1 base dir
  base=$(basename "$file")
  dir=$(dirname "$file")
  if ! printf '%s' "$base" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}-operation-[A-Za-z0-9-]+\.md$'; then
    err "$file" 1 filename "expected YYYY-MM-DD-operation-<title>.md"
  fi
  case "$dir" in
    "$ARTIFACTS"|"./$ARTIFACTS"|*"/$ARTIFACTS") ;;
    *) warn "$file" 1 location "one spec per file, all of them in $ARTIFACTS/";;
  esac
}


# every spec opens with the banner, so a half-written file is never mistaken for a spec
check_banner() {
  local file=$1 first
  first=$(sed -n '1p' "$file")
  if [ "$first" != "$BANNER" ]; then
    err "$file" 1 banner "line 1 must read '$BANNER'"
  fi
}

# "fields run in this order: goal, context, done when, fan out, rules, verify, output"
check_fields() {
  local file=$1 actual duplicate
  actual=$(grep -E '^[A-Z][A-Z ]*:' "$file" | sed 's/:.*//' || true)
  if [ "$actual" != "$EXPECTED_FIELDS" ]; then
    err "$file" 1 field_order "got $(printf '%s' "$actual" | tr '\n' '>' | sed 's/>$//')"
  fi
  duplicate=$(printf '%s' "$actual" | sort | uniq -d | tr '\n' ' ' || true)
  if [ -n "$duplicate" ]; then
    err "$file" 1 field_repeat "each field appears once; repeated: $duplicate"
  fi
}

# "every field appears exactly once, its key at column 1 and its value at column 15", and
# "continuation lines indent to column 15" — a ragged value column is the tell that a field
# was hand-edited, and it is what makes a spec unreadable at a glance
check_alignment() {
  local file=$1 lineno=0 line prefix
  while IFS= read -r line; do
    lineno=$((lineno + 1))
    if [ -z "$line" ]; then continue; fi
    # line 1 belongs to the banner check; reporting it twice names one cause as two faults
    if [ "$lineno" -eq 1 ]; then continue; fi
    case "$line" in
      "$BANNER") continue;;
      [A-Z]*:*)
        prefix=${line%%:*}
        if [ ${#line} -gt $((${#prefix} + 1)) ]; then
          case "$line" in
            "$prefix:$(printf '%*s' $((VALUE_COL - ${#prefix} - 2)) '')"[!\ ]*) ;;
            *) err "$file" "$lineno" alignment "the value starts off column $VALUE_COL";;
          esac
        fi
        continue;;
      "$(printf '%*s' $((VALUE_COL - 1)) '')"[!\ ]*) continue;;
      *) err "$file" "$lineno" alignment "a continuation line indents to column $VALUE_COL";;
    esac
  done < "$file"
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

# a spec that still carries the template's own instructions was copied, not written. these stems
# are the imperative openings of each field in graphs.md, and none survive a real answer
check_placeholders() {
  local file=$1 lineno text
  while IFS=: read -r lineno text; do
    if [ -z "$lineno" ]; then continue; fi
    err "$file" "$lineno" placeholder "template instruction left in place: ${text:0:40}"
  done < <(grep -nE '(restate the user|list the facts|list the observable|list the [0-9]+-[0-9]+ agent|define one uniform|list the rules every|describe a fresh agent|name the artifact executing)' "$file" || true)
}

# "a spec states constraints, never plan steps; a checkbox belongs in the artifact it produces"
check_no_steps() {
  local file=$1 lineno text
  while IFS=: read -r lineno text; do
    if [ -z "$lineno" ]; then continue; fi
    err "$file" "$lineno" plan_steps "a checkbox belongs in the artifact this spec produces"
  done < <(grep -nE '^[[:space:]]*- \[[ xX]\]' "$file" || true)
}

# "a numbered list runs 1..n with no gap, since renumbering by hand silently drops an entry"
# an unnumbered field is fine; a field that starts numbering has to finish the job
check_numbering() {
  local file=$1 name lineno text number expected
  for name in CONTEXT "DONE WHEN" "FAN OUT" RULES; do
    expected=1
    while IFS=$'\t' read -r lineno text; do
      number=$(printf '%s' "$text" | sed -n 's/^\([0-9]\{1,\}\)\. .*/\1/p')
      if [ -z "$number" ]; then continue; fi
      if [ "$number" -ne "$expected" ]; then
        err "$file" "$lineno" numbering "$name item $number where $expected was expected"
      fi
      expected=$((number + 1))
    done < <(field "$file" "$name")
  done
}

# "`fan out` names 2-5 agents, then closes with one unnumbered return shape" — the return shape
# is what makes the merge mechanical, and numbering it turns it into a sixth agent
check_fanout() {
  local file=$1 lineno text agents=0 shapes=0 shape_line=1
  while IFS=$'\t' read -r lineno text; do
    case "$text" in
      [0-9]*". "*) agents=$((agents + 1));;
      "return shape:"*) shapes=$((shapes + 1)); shape_line=$lineno;;
    esac
  done < <(field "$file" "FAN OUT")

  if [ "$agents" -lt "$MIN_AGENTS" ] || [ "$agents" -gt "$MAX_AGENTS" ]; then
    err "$file" 1 fanout_agents "$agents agents; the template allows $MIN_AGENTS-$MAX_AGENTS"
  fi
  if [ "$shapes" -eq 0 ]; then
    err "$file" 1 fanout_shape "fan out closes with one unnumbered return shape"
  elif [ "$shapes" -gt 1 ]; then
    err "$file" "$shape_line" fanout_shape "$shapes return shapes; handoffs need exactly one"
  fi
}

# "`--plan` means `.construct/retardify/plan/<same-basename>.md`" — the pairing is the whole reason a spec and
# the artifact it produces share a name, so a mismatched basename is a broken pair
check_output() {
  local file=$1 base named
  base=$(basename "$file")
  named=$(field "$file" OUTPUT | cut -f2- | grep -oE '.construct/retardify/plan/[A-Za-z0-9.-]+\.md' | head -n 1 || true)
  if [ -z "$named" ]; then
    warn "$file" 1 output_path "output names no .construct/retardify/plan/ path to pair with"
    return
  fi
  if [ "$(basename "$named")" != "$base" ]; then
    err "$file" 1 output_pairing "output names $(basename "$named"); the spec is $base"
  fi
}

# --- run list (add new checks here) ---
for spec in "${SPECS[@]}"; do
  check_filename     "$spec"
  check_banner       "$spec"
  check_fields       "$spec"
  check_alignment    "$spec"
  check_width        "$spec"
  check_placeholders "$spec"
  check_no_steps     "$spec"
  check_numbering    "$spec"
  check_fanout       "$spec"
  check_output       "$spec"
  scan_secrets       "$spec"
done

# ==============
# TELEMETRY
# ==============
ERRORS=$(grep -c '^ERROR|' "$FINDINGS" || true)
WARNINGS=$(grep -c '^WARN|' "$FINDINGS" || true)
SECRETS=$(grep -c '|secret|' "$FINDINGS" || true)

cat <<EOF

=== graph.sh sidecar ===
template: $TEMPLATE
scanned: ${#SPECS[@]} spec(s)
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
- context cites the repo or the user; a fact from neither source does not exist
- goal restates the user's goal, and never invents one the user did not ask for
- done when lists observable checks, each one falsifiable against the repo, a build or ci
- fan out splits on a real axis, and each agent answers a question the others do not
- rules bind every fanned agent, and name what stays out of scope
- verify attacks findings against done when and context, rather than approving them
- the spec was shown to the user, and fan out waited for an explicit go
- a key that reached a commit is already leaked; rotate it before rewriting anything
========================
EOF

if [ "$ERRORS" -gt 0 ]; then exit 1; fi
if [ "$STRICT" -eq 1 ] && [ "$WARNINGS" -gt 0 ]; then exit 1; fi
exit 0

#!/bin/bash
# =================================================================================
# @file guide.sh - build guide sidecar: names the target, then grades what landed
# =================================================================================
# @description
# PAIR
# - the only sidecar for `/retardify:guide`, which owns both halves of its own artifact
# - the doc carries the shape; this file names where it lands and grades what landed there
# - the input is a completed `/retardify:plan` file; the output is the ideal-path guide
# RUN
# - no flag runs the trigger half: it grades the source plan and names the guide target
# - `--check [paths]` runs the validator half; with no paths it grades the whole artifact dir
# - ERROR breaks a rule the doc states outright; WARN names a smell the doc tolerates
# @see plugins/retardify/skills/guide/SKILL.md, .construct/retardify/guide/, plugins/retardify/skills/plan/SKILL.md, plugins/retardify/shared/secrets.sh

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

  ARTIFACTS=".construct/retardify/guide"
  TEMPLATE="plugins/retardify/skills/guide/SKILL.md"
  VALIDATOR="plugins/retardify/skills/guide/guide.sh --check"

  PLAN="${1:-}"
  if [ -z "$PLAN" ]; then
    echo "fatal: /retardify:guide needs a plan, as in: /retardify:guide .construct/retardify/plan/<plan>.md" >&2
    exit 1
  fi
  if [ ! -f "$PLAN" ]; then
    echo "fatal: no such plan: $PLAN" >&2; exit 1; fi

  # an unchecked box is unfinished work, and a guide distilled from it narrates a build that
  # never happened; the doc reads `completed: no` and stops
  OPEN=$(grep -c '^- \[ \]' "$PLAN" || true)
  OPEN=${OPEN:-0}
  if [ "$OPEN" -eq 0 ]; then COMPLETED=yes; else COMPLETED=no; fi

  # the slug is the plan's own, minus the date and the operation prefix, so the guide carries
  # its source in its name; `-DONE` is the closed-plan suffix and never part of a title
  SLUG=$(basename "$PLAN" .md \
    | sed -E 's/^[0-9]{4}-[0-9]{2}-[0-9]{2}-//; s/^operation-//; s/-DONE$//' \
    | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-//; s/-$//')
  if [ -z "$SLUG" ]; then
    echo "fatal: the plan's name has no letters or digits to build a filename from" >&2; exit 1; fi

  mkdir -p "$ARTIFACTS"
  TARGET="$ARTIFACTS/$SLUG.md"
  if [ -e "$TARGET" ]; then COLLISION=yes; else COLLISION=no; fi
  EXISTING=$(find "$ARTIFACTS" -maxdepth 1 -type f -name '*.md' | wc -l | tr -d ' ')

  echo "=== /retardify:guide telemetry ==="
  echo "source: $PLAN"
  echo "open_boxes: $OPEN"
  echo "completed: $COMPLETED"
  echo "slug: $SLUG"
  echo "target: $TARGET"
  echo "collision: $COLLISION"
  echo "existing_guides: $EXISTING"
  echo "template: $TEMPLATE"
  echo "validator: $VALIDATOR"
  if [ "$COMPLETED" = no ]; then
    echo "--- stop ---"
    echo "$OPEN open box(es); a guide distills finished work, so close the plan first"
  fi
  if [ "$COLLISION" = yes ]; then
    echo "--- stop ---"
    echo "a guide already covers this plan; replacing it is the user's call, never the default"
  fi
  echo "==================================="
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
# every em dash in a guide is 3 bytes — a byte count would flag lines legally under the cap
UTF8_LOCALE=$(locale -a 2>/dev/null | grep -iE '^(C|en_US)\.(utf-?8)$' | head -n 1 || true)
if [ -n "$UTF8_LOCALE" ]; then export LC_ALL="$UTF8_LOCALE"; fi

MAX_WIDTH=100
STRICT=0
KEEP=0
TEMPLATE="plugins/retardify/skills/guide/SKILL.md"

# the template's own section order, which is the one thing every guide must agree on
EXPECTED_SECTIONS=$'Requires\nSteps\nDone'

# the words a perfect-world guide has no use for: each one writes for a failure the ideal run
# never meets, so a hit is an error rather than a style note
HEDGES='should|would|could|might|maybe|probably|optionally|otherwise|in case|edge case'
HEDGES="$HEDGES|if needed|if necessary|be careful|watch out|beware|warning|caveat"
HEDGES="$HEDGES|troubleshoot|workaround|fall ?back|roll ?back|retry|revert"

GUIDES=()
for arg in "$@"; do
  case "$arg" in
    --strict) STRICT=1;;
    --keep) KEEP=1;;
    -*) echo "fatal: unknown flag $arg" >&2; exit 1;;
    *) GUIDES+=("$arg");;
  esac
done

# no paths given: scan the whole artifact directory, anchored to the repo root so the default
# works from any subdirectory — same posture as the plan sidecar
if [ ${#GUIDES[@]} -eq 0 ]; then
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "fatal: not a git repository, and no paths given" >&2; exit 1; fi
  cd "$(git rev-parse --show-toplevel)"
  if [ ! -d .construct/retardify/guide ]; then echo "fatal: no .construct/retardify/guide/ to scan" >&2; exit 1; fi
  GUIDES=(.construct/retardify/guide/*.md)
fi

# a directory argument expands to the guides inside it
EXPANDED=()
for path in "${GUIDES[@]}"; do
  if [ -d "$path" ]; then
    for nested in "$path"/*.md; do [ -f "$nested" ] && EXPANDED+=("$nested"); done
  elif [ -f "$path" ]; then EXPANDED+=("$path")
  else echo "fatal: no such guide: $path" >&2; exit 1; fi
done
GUIDES=("${EXPANDED[@]}")

# repo-local scratch: the sandbox denies writes outside cwd, and macos mktemp ignores TMPDIR
TMPROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)/tmp"
TMPTAG=$(basename "${BASH_SOURCE[0]}" .sh)
mkdir -p "$TMPROOT"

# findings collect as "SEV|file|line|category|detail" — line is its own field so the report can
# sort numerically; joining it to the path first sorts 121 above 31. the run fails on ERROR only
FINDINGS=$(mktemp "$TMPROOT/$TMPTAG-findings.XXXXXX")
# a failed run leaves the findings behind to read; --keep does the same after a clean one
cleanup() { st=$?; if [ "$KEEP" -eq 0 ] && [ "$st" -eq 0 ]; then rm -f "$FINDINGS"; fi; }
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

# ==============
# CHECKS
#   each takes a guide path and appends findings; to add one, write a function and list it below
# ==============

# "`.construct/retardify/guide/<title>.md`, kebab-case, named by the plan it distills"
check_filename() {
  local file=$1 base dir
  base=$(basename "$file")
  dir=$(dirname "$file")
  if ! printf '%s' "$base" | grep -qE '^[a-z0-9]+(-[a-z0-9]+)*\.md$'; then
    err "$file" 1 filename "expected kebab-case <title>.md"
  fi
  case "$dir" in
    .construct/retardify/guide|./.construct/retardify/guide|*/.construct/retardify/guide) ;;
    *) warn "$file" 1 location "one guide per file, all of them in .construct/retardify/guide/";;
  esac
}

# "# GUIDE: Short Title" then "one line: what exists when the last step is done"
check_header() {
  local file=$1 title summary blank
  title=$(sed -n '1p' "$file")
  summary=$(sed -n '2p' "$file")
  blank=$(sed -n '3p' "$file")
  case "$title" in
    "# GUIDE: "*) ;;
    *) err "$file" 1 title "line 1 must read '# GUIDE: <title>'";;
  esac
  if [ -z "$summary" ] || [ "${summary:0:1}" = "#" ]; then
    err "$file" 2 summary "line 2 states what exists when the last step is done"
  fi
  if [ -n "$blank" ]; then
    err "$file" 3 summary "line 3 must be blank; the summary is one line and never wraps"
  fi
}

# "sections run in this order: requires, steps, done"
check_sections() {
  local file=$1 actual
  actual=$(grep -E '^## ' "$file" | sed 's/^## //' || true)
  if [ "$actual" != "$EXPECTED_SECTIONS" ]; then
    err "$file" 1 section_order "got $(printf '%s' "$actual" | tr '\n' '>' | sed 's/>$//')"
  fi
}

# "lines carry a single clause, capped at 100 characters, and never wrap"
check_width() {
  local file=$1 lineno=0 line
  while IFS= read -r line; do
    lineno=$((lineno + 1))
    if [ ${#line} -gt "$MAX_WIDTH" ]; then
      err "$file" "$lineno" width "${#line} chars; the cap is $MAX_WIDTH"
    fi
  done < "$file"
}

# a stray fence swallows the rest of the guide when rendered, so it is never cosmetic
check_fences() {
  local file=$1 count
  count=$(grep -cE '^[[:space:]]*```' "$file" || true)
  if [ $((count % 2)) -ne 0 ]; then
    err "$file" 1 fences "$count fence markers; one is unclosed"
  fi
}

# requires and done hold hyphen bullets only: a prerequisite is a fact and a check is a fact,
# and prose around either is the superfluous note the shape bans
check_bullets() {
  local file=$1 name lineno text
  for name in Requires Done; do
    while IFS=$'\t' read -r lineno text; do
      if [ -z "$text" ]; then continue; fi
      case "$text" in "- "*) continue;; esac
      err "$file" "$lineno" bullets "$name holds hyphen bullets only, one per line"
    done < <(section "$file" "$name")
  done
}

# stages are "### <n>. <name>" climbing by one; directives are numbered lines restarting at 1
# per stage; anything else between them is prose the shape has no room for
check_steps() {
  local file=$1 lineno text stage=0 directive=0 num infence=0 seen=0
  while IFS=$'\t' read -r lineno text; do
    if printf '%s' "$text" | grep -qE '^[[:space:]]*```'; then infence=$((1 - infence)); continue; fi
    if [ "$infence" -eq 1 ]; then continue; fi
    if [ -z "$text" ]; then continue; fi
    case "$text" in
      "### "*)
        if [ "$stage" -gt 0 ] && [ "$directive" -eq 0 ]; then
          err "$file" "$lineno" stage_empty "stage $stage holds no directives"
        fi
        num=$(printf '%s' "$text" | sed -n 's/^### \([0-9]\{1,\}\)\..*/\1/p')
        if [ -z "$num" ]; then
          err "$file" "$lineno" stage_header "stages are '### <n>. <name>'"
        elif [ "$num" -ne $((stage + 1)) ]; then
          err "$file" "$lineno" stage_order "stage $num follows $stage; stages climb by one"
        fi
        stage=${num:-$stage}
        directive=0
        seen=1
        continue;;
    esac
    num=$(printf '%s' "$text" | sed -n 's/^\([0-9]\{1,\}\)\. .*/\1/p')
    if [ -n "$num" ]; then
      if [ "$stage" -eq 0 ]; then
        err "$file" "$lineno" directive_stray "a directive sits above the first stage"
      elif [ "$num" -ne $((directive + 1)) ]; then
        err "$file" "$lineno" directive_order "directive $num follows $directive; each stage restarts at 1"
      fi
      directive=$num
      continue
    fi
    err "$file" "$lineno" steps_prose "steps hold stages and numbered directives only"
  done < <(section "$file" Steps)
  if [ "$stage" -gt 0 ] && [ "$directive" -eq 0 ]; then
    err "$file" 1 stage_empty "stage $stage holds no directives"
  fi
  if [ "$seen" -eq 0 ]; then
    err "$file" 1 steps_missing "no numbered stages under Steps"
  fi
}

# the one rule that makes a guide a guide: it writes for the likely case as fact, so a hedge
# is carried-over failure planning rather than a word choice
check_hedges() {
  local file=$1 lineno=0 line infence=0
  while IFS= read -r line; do
    lineno=$((lineno + 1))
    if printf '%s' "$line" | grep -qE '^[[:space:]]*```'; then infence=$((1 - infence)); continue; fi
    if [ "$infence" -eq 1 ]; then continue; fi
    if printf '%s' "$line" | grep -qiE "(^|[^a-z-])($HEDGES)([^a-z-]|$)"; then
      err "$file" "$lineno" hedge "a perfect-world guide states the likely case, never the failure"
    fi
  done < "$file"
}

# --- run list (add new checks here) ---
for guide in "${GUIDES[@]}"; do
  check_filename "$guide"
  check_header   "$guide"
  check_sections "$guide"
  check_width    "$guide"
  check_fences   "$guide"
  check_bullets  "$guide"
  check_steps    "$guide"
  check_hedges   "$guide"
  scan_secrets   "$guide"
done

# ==============
# TELEMETRY
# ==============
ERRORS=$(grep -c '^ERROR|' "$FINDINGS" || true)
WARNINGS=$(grep -c '^WARN|' "$FINDINGS" || true)
SECRETS=$(grep -c '|secret|' "$FINDINGS" || true)

cat <<EOF

=== guide.sh sidecar ===
template: $TEMPLATE
scanned: ${#GUIDES[@]} guide(s)
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
- distilled from a completed plan, never from one still open
- steps sort in ideal-build order, which is the order that needs no rework
- imperative voice, present tense; the likeliest case stated as fact
- every step assumes the one before it landed clean
- no caveat carried over from the plan, and none invented
- a claim with a number in it is verified against the plan, or it does not land
========================
EOF

if [ "$ERRORS" -gt 0 ]; then exit 1; fi
if [ "$STRICT" -eq 1 ] && [ "$WARNINGS" -gt 0 ]; then exit 1; fi
exit 0

#!/bin/bash
# ==============================================================================
# @file code.sh - boring-code sidecar: grades the logic inside one source file
# ==============================================================================
# @description
# PAIR
# - sidecar for `/retardify:code` — grades the mechanics its SKILL.md states outright
# - the doc carries the conventions and the audit shape; this file carries what a script judges
# - the logic inside a source file, which is the one thing `/retardify:file` leaves alone
# SCOPE
# - six mechanics, each a falsifiable count: ternaries, reduce, blank runs, depth, names
# - three are js idioms, so they run on the js family only; three run on every source file
# - what a script cannot judge stays in the checklist, the same posture file.sh holds
# RUN
# - `code.sh <path>` grades one file; the posttooluse hook calls it the same way
# - a leading slash reads as repo-relative, so `/src/app.ts` and `src/app.ts` name the same file
# - ERROR breaks a rule the doc states outright; WARN names a smell the doc tolerates
# - `--strict` promotes warnings to errors; exits 1 on any error
# @see plugins/retardify/skills/code/SKILL.md, plugins/retardify/skills/file/file.sh, plugins/operator/hooks/posttooluse/retardify-code.sh, .construct/retardify/code/

set -euo pipefail

# the doc is read only after this has already run, so help is refused here or not at all; the doc's
# own '## Help' section owns the output, which is why this prints a marker rather than a usage text
case " $* " in *" --help "*|*" -h "*) echo "help: requested"; exit 0;; esac

# the smoke case proves this file parses and its guards return; /test-skills reads the sources,
# the @see paths and the tool guards statically, so nothing here runs a step of the skill
case " $* " in *" --test "*) echo "test: ok"; exit 0;; esac

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "fatal: not a git repository" >&2; exit 1; fi
cd "$(git rev-parse --show-toplevel)"

ARTIFACTS=".construct/retardify/code"
TEMPLATE="plugins/retardify/skills/code/SKILL.md"

# "nesting caps at 2 levels" measured in columns, since a script cannot see a scope from a line
# 2 levels of a 2-space style is 4, so 8 leaves a full level of headroom before it complains
MAX_INDENT_COLS=8

# "a name caps at 25 characters and 4 words"
MAX_NAME_CHARS=25

# the js family, where a ternary, a `.reduce(` and a one-letter callback arg are all idioms
JS_EXT="js jsx ts tsx mjs cjs"

# every language this sidecar will grade at all; the rest carry none of these shapes
ALL_EXT="$JS_EXT go rs py rb java c h cpp hpp cc cs swift kt kts scala php dart sh bash zsh"

STRICT=0
FILE=""
for arg in "$@"; do
  case "$arg" in
    --strict) STRICT=1;;
    -*) echo "fatal: unknown flag $arg" >&2; exit 1;;
    *)
      if [ -n "$FILE" ]; then
        echo "fatal: one file per run; got '$FILE' and '$arg'" >&2; exit 1; fi
      FILE="$arg";;
  esac
done

if [ -z "$FILE" ]; then
  echo "fatal: /retardify:code needs a path, as in: /retardify:code src/utils/net.ts" >&2; exit 1; fi

# a leading slash reads as repo-relative first, since the doc's own example writes /folder/file.ext
FILE="${FILE#./}"
case "$FILE" in
  /*) if [ ! -f "$FILE" ] && [ -e "${FILE#/}" ]; then FILE="${FILE#/}"; fi;;
esac

if [ -d "$FILE" ]; then
  echo "fatal: '$FILE' is a directory; this sidecar grades exactly one source file" >&2; exit 1; fi
if [ ! -f "$FILE" ]; then
  echo "fatal: no such file: $FILE" >&2; exit 1; fi

EXT=${FILE##*.}
IS_JS=0
case " $JS_EXT " in *" $EXT "*) IS_JS=1;; esac
GRADED=0
case " $ALL_EXT " in *" $EXT "*) GRADED=1;; esac

# repo-local scratch: the sandbox denies writes outside cwd, and macos mktemp ignores TMPDIR
TMPROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)/tmp"
mkdir -p "$TMPROOT"
FINDINGS=$(mktemp "$TMPROOT/code-findings.XXXXXX")
cleanup() { st=$?; if [ "$st" -eq 0 ]; then rm -f "$FINDINGS"; fi; }
trap cleanup EXIT

err()  { printf 'ERROR|%s|%s|%s\n' "$1" "$2" "$3" >> "$FINDINGS"; }
warn() { printf 'WARN|%s|%s|%s\n' "$1" "$2" "$3" >> "$FINDINGS"; }

# a comment or a string can hold any shape it likes, so the js checks read code lines only
# this is deliberately crude: it drops full-line comments, which is where the false hits cluster
code_lines() {
  awk '{ line = $0; sub(/^[[:space:]]+/, "", line)
         if (line ~ /^(\/\/|\/\*|\*|#)/) next
         print NR "\t" $0 }' "$FILE"
}

# ==============
# CHECKS
#   each appends findings; to add one, write a function and list it in the run block below
# ==============

# "one ternary per expression; a second `?` nesting in is an if-statement wearing a costume"
# `??` and `?.` carry a question mark without being a ternary, so both are masked before counting
check_ternary() {
  local lineno text clean
  while IFS=$'\t' read -r lineno text; do
    clean=$(printf '%s' "$text" | sed -e 's/??//g' -e 's/?\.//g')
    if printf '%s' "$clean" | grep -qE '\?.*\?' && printf '%s' "$clean" | grep -q ':'; then
      err "$lineno" ternary "two ternaries in one expression; use an if-statement"
    fi
  done < <(code_lines)
}

# "no `.reduce(` where a for/forEach loop says the same thing plainer"
check_reduce() {
  local lineno text
  while IFS=$'\t' read -r lineno text; do
    case "$text" in
      *".reduce("*) warn "$lineno" reduce "use a for or forEach loop; it reads plainer";;
    esac
  done < <(code_lines)
}

# "spell it out" — bound to a parameter or a declaration position, since these bare words
# appear inside prose constantly and would drown every real hit
check_short_names() {
  local lineno text
  while IFS=$'\t' read -r lineno text; do
    if printf '%s' "$text" | grep -qE '(\(|,[[:space:]]*|(const|let|var)[[:space:]]+)(e|idx|el|cb)([[:space:]]*[,)=]|$)'; then
      warn "$lineno" short_name "spell the name out; e, idx, el and cb say nothing"
    fi
  done < <(code_lines)
}

# "one blank line between blocks, never two"
check_blank_runs() {
  local run=0 lineno=0 line
  while IFS= read -r line; do
    lineno=$((lineno + 1))
    if [ -z "$line" ]; then
      run=$((run + 1))
      if [ "$run" -eq 2 ]; then
        warn "$lineno" blank_run "two blank lines; one separates a block, two separate nothing"
      fi
    else run=0; fi
  done < "$FILE"
}

# "nesting caps at 2 levels; a third is a pyramid, so a guard or a helper flattens it"
check_nesting() {
  local lineno text indent
  while IFS=$'\t' read -r lineno text; do
    indent=$(printf '%s' "$text" | awk '{ match($0, /[^\t ]/); print RSTART - 1 }')
    if [ "${indent:-0}" -gt "$MAX_INDENT_COLS" ]; then
      warn "$lineno" nesting "$indent columns deep; flatten it with a guard or a helper"
    fi
  done < <(code_lines)
}

# "a name caps at 25 characters and 4 words; past either it is a sentence, not a name"
check_long_names() {
  local lineno text hit
  while IFS=$'\t' read -r lineno text; do
    hit=$({ printf '%s' "$text" | grep -oE "[A-Za-z_][A-Za-z0-9_]{$MAX_NAME_CHARS,}" || true; } | head -n 1)
    if [ -n "$hit" ]; then
      warn "$lineno" long_name "'${hit:0:32}' runs past $MAX_NAME_CHARS characters"
    fi
  done < <(code_lines)
}

# --- run list (add new checks here) ---
if [ "$GRADED" -eq 1 ]; then
  check_blank_runs
  check_nesting
  check_long_names
  if [ "$IS_JS" -eq 1 ]; then
    check_ternary
    check_reduce
    check_short_names
  fi
fi

# ==============
# TELEMETRY
# ==============
LINES=$(wc -l < "$FILE" | tr -d ' ')
ERRORS=$(grep -c '^ERROR|' "$FINDINGS" || true)
WARNINGS=$(grep -c '^WARN|' "$FINDINGS" || true)

# audit: one file per day, appended, matching the shape `/retardify:file` already lands
# reported, never created: the sidecar names the path and the count, the agent writes the entry
TODAYS_AUDIT="$ARTIFACTS/$(date +%Y-%m-%d).md"
if [ -f "$TODAYS_AUDIT" ];
then AUDIT_COUNT=$(grep -c '^## Code Audit #' "$TODAYS_AUDIT" || true)
else AUDIT_COUNT=0; fi
AUDIT_COUNT=${AUDIT_COUNT:-0}

cat <<EOF

=== code.sh sidecar ===
file: $FILE
audit_file: $TODAYS_AUDIT
audit_count: $AUDIT_COUNT
next_audit: $((AUDIT_COUNT + 1))
timestamp: $(date '+%Y-%m-%d %H:%M')
template: $TEMPLATE
lines: $LINES
graded: $(if [ "$GRADED" -eq 1 ]; then echo "yes, .$EXT"; else echo "no, .$EXT carries none of these shapes"; fi)
js_checks: $(if [ "$IS_JS" -eq 1 ]; then echo "on"; else echo "off, not a js family file"; fi)
indent_cap: $MAX_INDENT_COLS columns
name_cap: $MAX_NAME_CHARS chars
errors: $ERRORS
warnings: $WARNINGS
--- findings ---
EOF

if [ "$ERRORS" -eq 0 ] && [ "$WARNINGS" -eq 0 ]; then
  echo "none — every mechanic the doc states outright holds"
else
  sort -t'|' -k1,1 -k2,2n "$FINDINGS" \
    | awk -F'|' -v f="$FILE" '{ printf "%-5s %-50s %-11s %s\n", $1, f ":" $2, $3, $4 }'
fi

cat <<'EOF'
--- needs a human (first principles no script can judge) ---
VIBES
- DRY don't repeat yourself: if a block is written more than twice, extract it
- SoC separation of concerns: if a file does more than one thing, split it
- POLA least astonishment: if the obvious reading of the code is wrong, refactor it
NOT VIBES
- RDD resume-driven development: if a reader says 'he must be a senior dev', it's wrong
- WTF wtfs per min: if a reader says 'wtf' more than twice in a minute, it's wrong
- WET write everything twice: if a reader says "i think i've seen this before", it's wrong
=======================
EOF

if [ "$ERRORS" -gt 0 ]; then exit 1; fi
if [ "$STRICT" -eq 1 ] && [ "$WARNINGS" -gt 0 ]; then exit 1; fi
exit 0

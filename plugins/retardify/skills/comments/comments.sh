#!/bin/bash
# ===================================================
# @file comments.sh - comment shape validator sidecar
# ===================================================
# @description
# PAIR
# - sidecar for `check-comments` — asserts inline comments match the shape its SKILL.md documents
# - the doc carries the rules and the worked examples; this file carries what a script can judge
# - a spec, so its frontmatter names paths rather than a command, and it loads on a match
# SCOPE
# - source files, never a `docs/` artifact; `check-wayfinders` owns the header above them
# - full-line comments only: a trailing comment cannot be told from a string without a real parser
# - directives, section titles, banner runs and url lines are exempt, since none of them are prose
# RUN
# - defaults to every tracked source file; pass files or a directory to scope it
# - `--strict` promotes warnings to errors, `--keep` preserves scratch; exits 1 on any error
# - ERROR breaks a rule the doc states outright; WARN names a smell the doc tolerates
# - every rule needing judgement prints as a human checklist instead
# @see AGENTS.md, plugins/retardify/skills/comments/SKILL.md, plugins/retardify/skills/wayfinders/SKILL.md, plugins/retardify/skills/wayfinders/wayfinders.sh, plugins/retardify/shared/secrets.sh, plugins/operator/hooks/posttooluse.sh

set -euo pipefail

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
# every em dash in a type hint is 3 bytes — a byte count would flag lines that are legally under
UTF8_LOCALE=$(locale -a 2>/dev/null | grep -iE '^(C|en_US)\.(utf-?8)$' | head -n 1 || true)
if [ -n "$UTF8_LOCALE" ]; then export LC_ALL="$UTF8_LOCALE"; fi

MAX_WIDTH=100
STRICT=0
KEEP=0
TEMPLATE="plugins/retardify/skills/comments/SKILL.md"

# "a comment past 2 consecutive lines belongs in the wayfinding header instead"
MAX_BLOCK_LINES=2

# "one clause per line" — the same threshold logs.sh uses, since the smell is identical
MAX_COMMAS=3

# the marker map; an extension missing from both lists is skipped rather than guessed at
SLASH_EXT="js jsx ts tsx mjs cjs go rs java c h cpp hpp cc cs swift kt kts scala php dart"
HASH_EXT="sh bash zsh py rb yaml yml toml tf"

# vendored and generated trees are somebody else's comments, and a minified file is one long line
EXCLUDE_PATHS='(^|/)(node_modules|vendor|dist|build|out|coverage|\.next|\.venv|__pycache__)/'
EXCLUDE_FILES='\.min\.(js|css)$|\.d\.ts$|\.lock$'

# "directives are machine syntax, not prose" — these carry meaning to a tool, not to a reader
DIRECTIVES='eslint-|ts-ignore|ts-expect-error|ts-nocheck|prettier-ignore|biome-ignore|shellcheck|noqa|istanbul|jshint|globals?[[:space:]]|type:[[:space:]]*ignore|@ts-|oxlint|c8 ignore|v8 ignore'

# "banner runs of =, - or * decorate a header rather than saying anything"
BANNER='^[=*_~+-]{3,}$'

TARGETS=()
for arg in "$@"; do
  case "$arg" in
    --strict) STRICT=1;;
    --keep) KEEP=1;;
    -h|--help) sed -n '2,14p' "$0"; exit 0;;
    -*) echo "fatal: unknown flag $arg" >&2; exit 1;;
    *) TARGETS+=("$arg");;
  esac
done

# no paths given: every tracked source file, anchored to the repo root so the default works from
# any subdirectory — same posture as the @git* sidecars
if [ ${#TARGETS[@]} -eq 0 ]; then
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "fatal: not a git repository, and no paths given" >&2; exit 1; fi
  cd "$(git rev-parse --show-toplevel)"
  # a tracked path can be staged-deleted and gone from disk, which is not a caller's mistake
  while IFS= read -r tracked; do
    if [ -f "$tracked" ]; then TARGETS+=("$tracked"); fi
  done < <(git ls-files || true)
fi

# a directory argument expands to the files inside it, and every path is filtered by extension,
# so a caller can hand over a whole tree without hand-picking what this sidecar understands
FILES=()
consider() {
  local path=$1 ext
  if printf '%s' "$path" | grep -qE "$EXCLUDE_PATHS"; then return 0; fi
  if printf '%s' "$path" | grep -qE "$EXCLUDE_FILES"; then return 0; fi
  ext=${path##*.}
  case " $SLASH_EXT $HASH_EXT " in
    *" $ext "*) FILES+=("$path");;
  esac
}
for path in "${TARGETS[@]}"; do
  if [ -d "$path" ]; then
    while IFS= read -r nested; do consider "$nested"; done < <(find "$path" -type f || true)
  elif [ -f "$path" ]; then consider "$path"
  else echo "fatal: no such path: $path" >&2; exit 1; fi
done

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

marker_for() {
  local ext=${1##*.}
  case " $SLASH_EXT " in *" $ext "*) printf '//'; return 0;; esac
  case " $HASH_EXT " in *" $ext "*) printf '#'; return 0;; esac
  printf ''
}

# the wayfinding header is a different template's business, so report where it ends and start the
# comment checks after it; 0 means the file has no wayfinder and every comment line is in scope
wayfinder_end() {
  local file=$1 marker=$2
  if [ "$marker" = "#" ]; then
    awk '
      NR == 1 && /^#!/ { next }
      /^[[:space:]]*#/ { if ($0 ~ /@file/) seen = 1; last = NR; next }
      { exit }
      END { print (seen ? last : 0) }
    ' "$file"
  else
    awk '
      NR == 1 && /^#!/ { next }
      !opened && /^[[:space:]]*$/ { next }
      !opened && /^[[:space:]]*\/\*/ { opened = 1 }
      opened { if ($0 ~ /@file/) seen = 1; last = NR; if ($0 ~ /\*\//) exit; next }
      { exit }
      END { print (seen ? last : 0) }
    ' "$file"
  fi
}

# emit "LINENO<TAB>LINE" for every full-line comment below the wayfinder
comment_lines() {
  local file=$1 marker=$2 skip=$3
  if [ "$marker" = "#" ]; then
    awk -v skip="$skip" 'NR > skip && /^[[:space:]]*#/ { print NR "\t" $0 }' "$file"
  else
    awk -v skip="$skip" 'NR > skip && /^[[:space:]]*\/\// { print NR "\t" $0 }' "$file"
  fi
}

# the comment's prose, with indentation, marker and one following space removed
body_of() {
  printf '%s' "$1" | sed -E 's/^[[:space:]]*//; s|^(#+\|/+)[[:space:]]?||'
}

# a line nobody should be judged on: machine syntax, decoration, or a section header
exempt() {
  local body=$1
  if [ -z "$body" ]; then return 0; fi
  if printf '%s' "$body" | grep -qE "$DIRECTIVES"; then return 0; fi
  if printf '%s' "$body" | grep -qE "$BANNER"; then return 0; fi
  # "`// SECTION TITLE` headers break a long file into parts, and stay uppercase"
  if printf '%s' "$body" | grep -qE '^[A-Z][A-Z0-9 _&/-]*$'; then return 0; fi
  return 1
}

# ==============
# CHECKS
#   each takes a file path and appends findings; to add one, write a function and list it below
# ==============

# "exactly one space after the marker, so `// like this` and never `//like this`"
check_spacing() {
  local file=$1 marker=$2 skip=$3 lineno line trimmed
  while IFS=$'\t' read -r lineno line; do
    trimmed=$(printf '%s' "$line" | sed -E 's/^[[:space:]]*//')
    if printf '%s' "$trimmed" | grep -qE "$BANNER"; then continue; fi
    # the trailing class excludes the marker char itself, or `/+` backtracks to one slash and
    # lets the second slash satisfy "not a space", flagging every correctly spaced `// text`
    if printf '%s' "$trimmed" | grep -qE '^(#+[^#[:space:]]|/+[^/[:space:]])'; then
      err "$file" "$lineno" spacing "one space after the marker, so '${marker} text' not '${marker}text'"
    fi
  done < <(comment_lines "$file" "$marker" "$skip")
}

# "`lines` carry a single clause, capped at 100 characters, and never wrap"
check_width() {
  local file=$1 marker=$2 skip=$3 lineno line
  while IFS=$'\t' read -r lineno line; do
    # "a line carrying a url is exempt from the width cap, since it cannot be wrapped"
    if printf '%s' "$line" | grep -qE '[a-z][a-z0-9+.-]*://'; then continue; fi
    if [ ${#line} -gt "$MAX_WIDTH" ]; then
      err "$file" "$lineno" width "${#line} chars; the cap is $MAX_WIDTH, so split it by clause"
    fi
  done < <(comment_lines "$file" "$marker" "$skip")
}

# "lowercase shorthand english, comma separated, never sentence case" — an all-caps first word is
# an acronym or a section header, and neither is somebody writing prose in sentence case
check_casing() {
  local file=$1 marker=$2 skip=$3 lineno line body first
  while IFS=$'\t' read -r lineno line; do
    body=$(body_of "$line")
    if exempt "$body"; then continue; fi
    first=${body%% *}
    if printf '%s' "$first" | grep -qE '^[A-Z0-9_]+[.,:;!?]?$'; then continue; fi
    if printf '%s' "$body" | grep -qE '^[A-Z]'; then
      err "$file" "$lineno" casing "lowercase shorthand, never sentence case: '${body:0:32}'"
    fi
  done < <(comment_lines "$file" "$marker" "$skip")
}

# "no trailing period, since a comment is a label and not a sentence"
check_period() {
  local file=$1 marker=$2 skip=$3 lineno line body
  while IFS=$'\t' read -r lineno line; do
    body=$(body_of "$line")
    if exempt "$body"; then continue; fi
    # an abbreviation, an ellipsis or a version number ends in a dot without being a sentence
    if printf '%s' "$body" | grep -qE '(\.\.\.|[0-9]\.|e\.g\.|i\.e\.|etc\.|vs\.|\bal\.)$'; then continue; fi
    if printf '%s' "$body" | grep -qE '[[:alnum:])"'"'"']\.$'; then
      warn "$file" "$lineno" period "drop the trailing period; a comment is a label, not a sentence"
    fi
  done < <(comment_lines "$file" "$marker" "$skip")
}

# "`lines` carry a single clause" — the same comma-chain smell logs.sh reports
check_clause() {
  local file=$1 marker=$2 skip=$3 lineno line body commas
  while IFS=$'\t' read -r lineno line; do
    body=$(body_of "$line")
    if exempt "$body"; then continue; fi
    commas=$(printf '%s' "$body" | tr -cd ',' | wc -c | tr -d ' ')
    if [ "$commas" -ge "$MAX_COMMAS" ]; then
      warn "$file" "$lineno" clause "$commas commas; one clause per line reads faster"
    fi
  done < <(comment_lines "$file" "$marker" "$skip")
}

# "a comment past 2 consecutive lines belongs in the wayfinding header instead"
check_block() {
  local file=$1 marker=$2 skip=$3 lineno line body run=0 start=0 prev=0
  while IFS=$'\t' read -r lineno line; do
    body=$(body_of "$line")
    if exempt "$body"; then run=0; prev=0; continue; fi
    if [ "$prev" -ne 0 ] && [ "$lineno" -eq $((prev + 1)) ]; then
      run=$((run + 1))
    else
      run=1; start=$lineno
    fi
    prev=$lineno
    if [ "$run" -eq $((MAX_BLOCK_LINES + 1)) ]; then
      warn "$file" "$start" block "$run+ comment lines; a file-level note belongs in the wayfinder"
    fi
  done < <(comment_lines "$file" "$marker" "$skip")
}

# "commented-out code gets deleted, since git already remembers it" — conservative on purpose:
# a bare trailing `;` is NOT a signal, since prose in this house style joins its clauses with one
CODE_SHAPES='^(const|let|var|function|class|import|export|def|fn)[[:space:]]+[a-zA-Z_$]'
CODE_SHAPES="$CODE_SHAPES"'|^[a-zA-Z_$][a-zA-Z0-9_$.]*\(.*\);?$'
CODE_SHAPES="$CODE_SHAPES"'|^(if|for|while|switch)[[:space:]]*\('
CODE_SHAPES="$CODE_SHAPES"'|^[a-zA-Z_$][a-zA-Z0-9_$.]*[[:space:]]*[-+*/]?=.*;$'
CODE_SHAPES="$CODE_SHAPES"'|=>.*[;{]$'

check_commented_code() {
  local file=$1 marker=$2 skip=$3 lineno line body
  while IFS=$'\t' read -r lineno line; do
    body=$(body_of "$line")
    if exempt "$body"; then continue; fi
    if printf '%s' "$body" | grep -qE "$CODE_SHAPES"; then
      warn "$file" "$lineno" commented_code "looks like code; delete it, git already remembers it"
    fi
  done < <(comment_lines "$file" "$marker" "$skip")
}

# a prose block comment below the wayfinder is a wayfinder that lost its way, or a paragraph that
# should have been `//` lines; either way it is the shape this template does not want
check_block_comment() {
  local file=$1 marker=$2 skip=$3 hit
  if [ "$marker" != "//" ]; then return 0; fi
  while IFS= read -r hit; do
    if [ -z "$hit" ]; then continue; fi
    warn "$file" "${hit%%:*}" block_comment "block comment below the wayfinder; use // lines instead"
  done < <(awk -v skip="$skip" '
    NR > skip && /^[[:space:]]*\/\*/ && !/\*\//  { print NR ":" $0 }
  ' "$file" || true)
}

# --- run list (add new checks here) ---
for file in "${FILES[@]}"; do
  MARKER=$(marker_for "$file")
  if [ -z "$MARKER" ]; then continue; fi
  SKIP=$(wayfinder_end "$file" "$MARKER")
  check_spacing        "$file" "$MARKER" "$SKIP"
  check_width          "$file" "$MARKER" "$SKIP"
  check_casing         "$file" "$MARKER" "$SKIP"
  check_period         "$file" "$MARKER" "$SKIP"
  check_clause         "$file" "$MARKER" "$SKIP"
  check_block          "$file" "$MARKER" "$SKIP"
  check_commented_code "$file" "$MARKER" "$SKIP"
  check_block_comment  "$file" "$MARKER" "$SKIP"
  scan_secrets         "$file"
done

# ==============
# TELEMETRY
# ==============
ERRORS=$(grep -c '^ERROR|' "$FINDINGS" || true)
WARNINGS=$(grep -c '^WARN|' "$FINDINGS" || true)
SECRETS=$(grep -c '|secret|' "$FINDINGS" || true)

# audit: one file per day per kind, so two triggers on the same day never interleave one file
# reported, never created: the sidecar names the path and the count, the agent writes the entry
AUDIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
TODAYS_AUDIT="audits/comments/$(date +%Y-%m-%d).md"
if [ -f "$AUDIT_ROOT/$TODAYS_AUDIT" ];
then AUDIT_COUNT=$(grep -c '^## Comments Audit #' "$AUDIT_ROOT/$TODAYS_AUDIT" || true)
else AUDIT_COUNT=0; fi
AUDIT_COUNT=${AUDIT_COUNT:-0}

cat <<EOF

=== comments.sh sidecar ===
audit_file: $TODAYS_AUDIT
audit_count: $AUDIT_COUNT
next_audit: $((AUDIT_COUNT + 1))
timestamp: $(date '+%Y-%m-%d %H:%M')
template: $TEMPLATE
scanned: ${#FILES[@]} source file(s)
width_cap: $MAX_WIDTH chars
block_cap: $MAX_BLOCK_LINES consecutive lines
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
- every comment says WHY the code exists, not what it does, unless the code is genuinely hard
- a comment restating the line below it is deleted, since the code already said that
- an unclear line gets refactored for legibility before it gets explained in prose
- more comments is good; more comments that carry no information is noise
- a trailing comment is never scanned here, so its shape is on you: `// retry budget — seconds`
- a comment that drifted from the code it describes is worse than no comment at all
- a key that reached a commit is already leaked; rotate it before rewriting anything
========================
EOF

if [ "$ERRORS" -gt 0 ]; then exit 1; fi
if [ "$STRICT" -eq 1 ] && [ "$WARNINGS" -gt 0 ]; then exit 1; fi
exit 0

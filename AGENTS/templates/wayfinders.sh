#!/bin/bash
# ==========================================================
# @file wayfinders.sh - wayfinding header validator sidecar
# ==========================================================
# @description
# - sidecar for `wayfinders.md` — asserts a wayfinding header matches the shape it documents
# - one check per machine-checkable rule; every rule needing judgement prints as a human checklist
# - ERROR breaks a rule the template states outright; WARN names a smell the template tolerates
# - the header only; everything below it is `AGENTS/templates/comments.sh`'s to judge
# - a broken `@see` only warns here, and nothing gates references now, so the warn is all there is
# - defaults to every tracked eligible file; pass files or a directory to scope it
# - `--strict` promotes warnings to errors, `--keep` preserves scratch; exits 1 on any error
# @see AGENTS.md, AGENTS/settings/secrets.sh, AGENTS/templates/wayfinders.md, AGENTS/skills/gitinsights/gitinsights.sh

set -euo pipefail

# ==============
# PREFLIGHT
# ==============
# the shared scan sits beside this file, not beside the repo being scanned: resolve them before
# anything cds to a repo root, since BASH_SOURCE arrives relative and would follow that cd
SHARED=$(cd "$(dirname "${BASH_SOURCE[0]}")/../settings" 2>/dev/null && pwd || true)
if [ ! -f "$SHARED/secrets.sh" ]; then
  echo "fatal: no AGENTS/settings/secrets.sh beside this sidecar" >&2; exit 1; fi
# shellcheck source=../settings/secrets.sh
. "$SHARED/secrets.sh"

# character counts, not byte counts: bash's ${#var} is multibyte-aware under a utf-8 locale, and
# every em dash in a description is 3 bytes — a byte count would flag lines legally under the cap
UTF8_LOCALE=$(locale -a 2>/dev/null | grep -iE '^(C|en_US)\.(utf-?8)$' | head -n 1 || true)
if [ -n "$UTF8_LOCALE" ]; then export LC_ALL="$UTF8_LOCALE"; fi

MAX_WIDTH=100
STRICT=0
KEEP=0
TEMPLATE="AGENTS/templates/wayfinders.md"

# "the tags appear once each, in that order"
EXPECTED_TAGS=$'file\ndescription\nsee'

# a banner is decoration, so an exact match would fail on every file for no reader benefit
BANNER_TOLERANCE=2

# "eligible files are the js family and shell", since those are what carry the block
SLASH_EXT="js jsx ts tsx mjs cjs"
HASH_EXT="sh bash zsh"

# vendored and generated trees carry somebody else's headers, and a bundle has none worth reading
EXCLUDE_PATHS='(^|/)(node_modules|vendor|dist|build|out|coverage|\.next|\.venv)/'
EXCLUDE_FILES='\.min\.(js|css)$|\.d\.ts$'

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

# no paths given: every tracked eligible file, anchored to the repo root so the default works
# from any subdirectory — same posture as the @git* sidecars
if [ ${#TARGETS[@]} -eq 0 ]; then
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "fatal: not a git repository, and no paths given" >&2; exit 1; fi
  cd "$(git rev-parse --show-toplevel)"
  # a tracked path can be staged-deleted and gone from disk, which is not a caller's mistake
  while IFS= read -r tracked; do
    if [ -f "$tracked" ]; then TARGETS+=("$tracked"); fi
  done < <(git ls-files || true)
fi

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
SCRATCH=$(mktemp -d "$TMPROOT/$TMPTAG-scratch.XXXXXX")
# a failed run leaves scratch behind to read; --keep does the same after a clean one
cleanup() { st=$?; if [ "$KEEP" -eq 0 ] && [ "$st" -eq 0 ]; then rm -rf "$FINDINGS" "$SCRATCH"; fi; }
trap cleanup EXIT

err()  { printf 'ERROR|%s|%s|%s|%s\n' "$1" "$2" "$3" "$4" >> "$FINDINGS"; }
warn() { printf 'WARN|%s|%s|%s|%s\n' "$1" "$2" "$3" "$4" >> "$FINDINGS"; }

# a reference that only resolves once this repo is symlinked into a host project; the same two
# lists gitinsights.sh keeps, since both tools answer "is this path missing or just elsewhere"
is_host_only() {
  case "$1" in
    AGENTS.md) return 0;;
    .claude|.claude/*|.grok|.grok/*) return 0;;
    eslint.config.mjs) return 0;;
    .github/workflows/deploy.yml) return 0;;
    *) return 1;;
  esac
}
is_generated() {
  case "$1" in
    *tests/report*|*tests/results*|*.next*|*node_modules*) return 0;;
    docs/logs*|docs/plans*|docs/study*|docs/audits*|docs/honest*|docs/insights*|docs/graphs*) return 0;;
    *) return 1;;
  esac
}

style_for() {
  local ext=${1##*.}
  case " $SLASH_EXT " in *" $ext "*) printf 'jsdoc'; return 0;; esac
  case " $HASH_EXT " in *" $ext "*) printf 'hash'; return 0;; esac
  printf ''
}

# emit "LINENO<TAB>LINE" for the leading comment block, which is where a wayfinder has to live
block_lines() {
  local file=$1 style=$2
  if [ "$style" = "hash" ]; then
    awk '
      NR == 1 && /^#!/ { next }
      /^[[:space:]]*#/ { print NR "\t" $0; next }
      { exit }
    ' "$file"
  else
    awk '
      NR == 1 && /^#!/ { next }
      !opened && /^[[:space:]]*$/ { next }
      !opened && /^[[:space:]]*\/\*/ { opened = 1 }
      opened { print NR "\t" $0; if ($0 ~ /\*\//) exit; next }
      { exit }
    ' "$file"
  fi
}

# the comment scaffolding of either style, stripped; ERE throughout, since BSD sed supports
# neither `\b` nor `\|` in a basic expression and would silently match nothing on macos
STRIP='s/^[[:space:]]*//; s|^/\*+||; s|\*/[[:space:]]*$||; s/^\*[[:space:]]?//; s/^#[[:space:]]?//'

# the line's prose, with that scaffolding removed
content_of() {
  printf '%s' "$1" | sed -E "$STRIP"
}

# the whole header as prose, in one sed call rather than one per line
block_content() {
  block_lines "$1" "$2" | cut -f2- | sed -E "$STRIP"
}

# ==============
# CHECKS
#   each takes a file path and appends findings; to add one, write a function and list it below
# ==============

# "eligible files carry the block" — a warn, since a fresh host project has not been through yet
check_present() {
  local file=$1 style=$2
  if block_lines "$file" "$style" | cut -f2- | grep -q '@file'; then return 0; fi
  warn "$file" 1 no_wayfinder "no wayfinding header; add one so a reader learns the file's edges"
  return 1
}

# "the block opens on line 1, or line 1 after a shebang, with nothing above it"
# frontmatter needs no branch here: only source extensions reach this, and none of them carry yaml
check_position() {
  local file=$1 style=$2 first expected=1
  if head -n 1 "$file" | grep -q '^#!'; then expected=2; fi
  first=$(block_lines "$file" "$style" | head -n 1 | cut -f1)
  if [ -z "$first" ]; then return 0; fi
  if [ "$first" -ne "$expected" ]; then
    err "$file" "$first" position "the header opens on line $expected, with nothing above it"
  fi
}

# "@file, @description and @see each appear once, in that order"
check_tags() {
  local file=$1 style=$2 actual tag count
  actual=$(block_content "$file" "$style" | sed -E -n 's/^@(file|description|see)([[:space:]].*)?$/\1/p')
  if [ "$actual" != "$EXPECTED_TAGS" ]; then
    err "$file" 1 tag_order "got $(printf '%s' "$actual" | tr '\n' '>' | sed 's/>$//'); want file>description>see"
  fi
  for tag in file description see; do
    count=$(printf '%s\n' "$actual" | grep -c "^$tag$" || true)
    if [ "$count" -gt 1 ]; then
      err "$file" 1 tag_repeat "@$tag appears $count times; each tag appears once"
    fi
  done
}

# "@file reads <filename> - <short, specific title>, and the filename is the real one"
check_file_tag() {
  local file=$1 style=$2 lineno line named base
  base=$(basename "$file")
  while IFS=$'\t' read -r lineno line; do
    case "$(content_of "$line")" in
      "@file "*) ;;
      *) continue;;
    esac
    named=$(content_of "$line" | sed -n 's/^@file[[:space:]]\{1,\}\([^[:space:]]\{1,\}\).*/\1/p')
    if [ "$named" != "$base" ]; then
      err "$file" "$lineno" file_tag "@file names '$named'; this file is '$base'"
    fi
    if ! content_of "$line" | grep -qE '^@file[[:space:]]+[^[:space:]]+[[:space:]]+-[[:space:]]+.+'; then
      err "$file" "$lineno" file_tag "@file reads '$base - <short, specific title>'"
    fi
    return 0
  done < <(block_lines "$file" "$style")
}

# "a banner of = sits above and below the @file line, matching its width"
check_banner() {
  local file=$1 style=$2 lineno line above below width target found=0
  while IFS=$'\t' read -r lineno line; do
    case "$(content_of "$line")" in
      "@file "*) found=$lineno; width=${#line};;
    esac
  done < <(block_lines "$file" "$style")
  if [ "$found" -eq 0 ]; then return 0; fi
  above=$(sed -n "$((found - 1))p" "$file" 2>/dev/null || true)
  below=$(sed -n "$((found + 1))p" "$file" 2>/dev/null || true)
  for target in "$above" "$below"; do
    if ! content_of "$target" | grep -qE '^=+$'; then
      warn "$file" "$found" banner "a banner of = sits above and below @file"
      return 0
    fi
  done
  if [ $(( ${#above} > width ? ${#above} - width : width - ${#above} )) -gt "$BANNER_TOLERANCE" ]; then
    warn "$file" "$found" banner "banner is ${#above} wide against a $width wide @file line"
  fi
}

# "@description is a hyphen delimited list of single clause lines that never wrap" — a line that
# is neither a tag, a bullet nor an uppercase group heading is the tail of a wrapped clause
check_description() {
  local file=$1 style=$2 lineno line text inside=0 bullets=0
  while IFS=$'\t' read -r lineno line; do
    text=$(content_of "$line")
    case "$text" in
      "@description"*) inside=1; continue;;
      "@see"*) inside=0; continue;;
      "@"*) continue;;
    esac
    if [ "$inside" -eq 0 ]; then continue; fi
    case "$text" in ""|"="*) continue;; esac
    case "$text" in
      "-"*|"* "*) bullets=$((bullets + 1)); continue;;
    esac
    # an uppercase word alone on a line groups the block, the way this template's own header does
    if printf '%s' "$text" | grep -qE '^[A-Z][A-Z0-9 _/-]*$'; then continue; fi
    warn "$file" "$lineno" wrapped "hyphen delimited single clauses; this line reads as a wrap"
  done < <(block_lines "$file" "$style")
  if [ "$bullets" -eq 0 ]; then
    err "$file" 1 description "no @description bullets; say what the file is for in one clause each"
  fi
}

# "@see is a comma separated list of ALL related internal files"
check_see() {
  local file=$1 style=$2 lineno line paths token ref
  while IFS=$'\t' read -r lineno line; do
    case "$(content_of "$line")" in
      "@see "*) ;;
      *) continue;;
    esac
    paths=$(content_of "$line" | sed -n 's/^@see[[:space:]]\{1,\}\(.*\)/\1/p')
    if [ -z "$paths" ]; then
      err "$file" "$lineno" see_empty "@see lists every related internal file"
      return 0
    fi
    case "$paths" in *"{@link"*|*http*) return 0;; esac
    for token in $(printf '%s' "$paths" | tr ',' ' '); do
      ref=${token#/}; ref=${ref%/}
      if [ -z "$ref" ]; then continue; fi
      # bare prose words are not references; only path-shaped tokens get resolved
      case "$ref" in */*|*.*) ;; *) continue;; esac
      if is_host_only "$ref" || is_generated "$ref"; then continue; fi
      if [ ! -e "$ref" ]; then
        warn "$file" "$lineno" see_unresolved "@see '$token' resolves to nothing from the repo root"
      fi
    done
    return 0
  done < <(block_lines "$file" "$style")
}

# "lines carry a single clause, capped at 100 characters"
check_width() {
  local file=$1 style=$2 lineno line
  while IFS=$'\t' read -r lineno line; do
    # a @see list names every related file and cannot be split without breaking the tag
    case "$(content_of "$line")" in "@see "*) continue;; esac
    if [ ${#line} -gt "$MAX_WIDTH" ]; then
      err "$file" "$lineno" width "${#line} chars; the cap is $MAX_WIDTH"
    fi
  done < <(block_lines "$file" "$style")
}

# "lowercase shorthand english" — an all-caps first word is an acronym or a group heading
check_casing() {
  local file=$1 style=$2 lineno line text body first
  while IFS=$'\t' read -r lineno line; do
    text=$(content_of "$line")
    case "$text" in "-"*) body=$(printf '%s' "$text" | sed -E 's/^-[[:space:]]*//');; *) continue;; esac
    if [ -z "$body" ]; then continue; fi
    first=${body%% *}
    if printf '%s' "$first" | grep -qE '^[A-Z0-9_]+[.,:;!?]?$'; then continue; fi
    if printf '%s' "$body" | grep -qE '^[A-Z]'; then
      warn "$file" "$lineno" casing "lowercase shorthand: '${body:0:32}'"
    fi
  done < <(block_lines "$file" "$style")
}

# --- run list (add new checks here) ---
for file in "${FILES[@]}"; do
  STYLE=$(style_for "$file")
  if [ -z "$STYLE" ]; then continue; fi
  # every remaining check reads the header, so a file without one has nothing to say about it
  if ! check_present "$file" "$STYLE"; then continue; fi
  check_position    "$file" "$STYLE"
  check_tags        "$file" "$STYLE"
  check_file_tag    "$file" "$STYLE"
  check_banner      "$file" "$STYLE"
  check_description "$file" "$STYLE"
  check_see         "$file" "$STYLE"
  check_width       "$file" "$STYLE"
  check_casing      "$file" "$STYLE"
  scan_secrets      "$file"
done

# ==============
# TELEMETRY
# ==============
ERRORS=$(grep -c '^ERROR|' "$FINDINGS" || true)
WARNINGS=$(grep -c '^WARN|' "$FINDINGS" || true)
SECRETS=$(grep -c '|secret|' "$FINDINGS" || true)

cat <<EOF

=== wayfinders.sh sidecar ===
template: $TEMPLATE
scanned: ${#FILES[@]} eligible file(s)
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
- the header says what the file is FOR and where its edges are, never how it works
- every tag reflects the file as it now stands, since a drifted tag misleads worse than none
- @see names what a reader opens next, not every module the file happens to import
- the title is specific enough to tell this file apart from its neighbours
- a description line carries one clause, and the block stays scannable at a glance
- a key that reached a commit is already leaked; rotate it before rewriting anything
========================
EOF

if [ "$ERRORS" -gt 0 ]; then exit 1; fi
if [ "$STRICT" -eq 1 ] && [ "$WARNINGS" -gt 0 ]; then exit 1; fi
exit 0

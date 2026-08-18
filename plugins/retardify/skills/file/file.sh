#!/bin/bash
# ==================================================
# @file file.sh - source file shape validator sidecar
# ==================================================
# @description
# PAIR
# - sidecar for `/retardify:file` — asserts a source file matches the shape its SKILL.md documents
# - the doc carries the four conventions and their examples; this file carries what a script judges
# - everything about a source file except the logic itself, which `/retardify:code` owns
# SCOPE
# - four conventions in one pass: naming, the wayfinding header, module order, inline comments
# - two eligibility lists, since a wayfinder belongs only to the js family and shell
# - comments are checked across every language that carries a full-line marker
# - source files, never a `.construct/` artifact; the artifact it writes is graded here too
# RUN
# - defaults to every tracked eligible file; pass files or a directory to scope it
# - a scoped run answers about those paths only, so the artifact sweep is a bare-run check
# - `--strict` promotes warnings to errors, `--keep` preserves scratch; exits 1 on any error
# - ERROR breaks a rule the doc states outright; WARN names a smell the doc tolerates
# - a broken `@see` only warns, since nothing gates references; `/retardify:todo` reports repo-wide
# @see plugins/retardify/skills/file/SKILL.md, plugins/retardify/skills/todo/todo.sh, plugins/operator/hooks/posttooluse/retardify-file.sh, plugins/retardify/shared/secrets.sh, .construct/retardify/file/

set -euo pipefail

# the doc is read only after this has already run, so help is refused here or not at all; the doc's
# own '## Help' section owns the output, which is why this prints a marker rather than a usage text
case " $* " in *" --help "*|*" -h "*) echo "help: requested"; exit 0;; esac

# the smoke case proves this file parses and its guards return; /test-skills reads the sources,
# the @see paths and the tool guards statically, so nothing here runs a step of the skill
case " $* " in *" --test "*) echo "test: ok"; exit 0;; esac

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
# every em dash in a description is 3 bytes — a byte count would flag lines legally under the cap
UTF8_LOCALE=$(locale -a 2>/dev/null | grep -iE '^(C|en_US)\.(utf-?8)$' | head -n 1 || true)
if [ -n "$UTF8_LOCALE" ]; then export LC_ALL="$UTF8_LOCALE"; fi

MAX_WIDTH=100
STRICT=0
KEEP=0
TEMPLATE="plugins/retardify/skills/file/SKILL.md"

# "a comment past 2 consecutive lines belongs in the wayfinding header instead"
MAX_BLOCK_LINES=2

# "one clause per line" — the same threshold log.sh uses, since the smell is identical
MAX_COMMAS=3

# "the tags appear once each, in that order"
EXPECTED_TAGS=$'file\ndescription\nsee'

# a banner is decoration, so an exact match would fail on every file for no reader benefit
BANNER_TOLERANCE=2

# comments reach every language carrying a full-line marker, which is the wide list
SLASH_EXT="js jsx ts tsx mjs cjs go rs java c h cpp hpp cc cs swift kt kts scala php dart"
HASH_EXT="sh bash zsh py rb yaml yml toml tf"

# a wayfinder belongs only to the js family and shell, which is the narrow list. the two scopes
# stay separate on purpose: a go file gets its comments graded and is never asked for a header
WAYFINDER_SLASH="js jsx ts tsx mjs cjs"
WAYFINDER_HASH="sh bash zsh"

# module order is a js/ts convention; nothing else in the wide list carries an import block
MODULE_EXT="js jsx ts tsx mjs cjs"

# vendored and generated trees are somebody else's files, and a minified file is one long line
EXCLUDE_PATHS='(^|/)(node_modules|vendor|dist|build|out|coverage|\.next|\.venv|__pycache__)/'
EXCLUDE_FILES='\.min\.(js|css)$|\.d\.ts$|\.lock$'

# "directives are machine syntax, not prose" — these carry meaning to a tool, not to a reader
DIRECTIVES='eslint-|ts-ignore|ts-expect-error|ts-nocheck|prettier-ignore|biome-ignore|shellcheck|noqa|istanbul|jshint|globals?[[:space:]]|type:[[:space:]]*ignore|@ts-|oxlint|c8 ignore|v8 ignore'

# "banner runs of =, - or * decorate a header rather than saying anything"
BANNER='^[=*_~+-]{3,}$'

TARGETS=()
# a caller naming paths asked about those paths; the artifact sweep below reports on files it was
# never handed, which reads as noise about an unrelated file on every posttooluse run
SCOPED=0
for arg in "$@"; do
  case "$arg" in
    --strict) STRICT=1;;
    --keep) KEEP=1;;
    -*) echo "fatal: unknown flag $arg" >&2; exit 1;;
    *) TARGETS+=("$arg"); SCOPED=1;;
  esac
done

# no paths given: every tracked source file, anchored to the repo root so the default works from
# any subdirectory — same posture as the gitgud sidecars
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

# ==============
# SHARED READERS
# ==============

marker_for() {
  local ext=${1##*.}
  case " $SLASH_EXT " in *" $ext "*) printf '//'; return 0;; esac
  case " $HASH_EXT " in *" $ext "*) printf '#'; return 0;; esac
  printf ''
}

# the wayfinder style, or empty when the extension carries no header at all; this is the narrow
# list, so a go file returns empty here and still gets its comments graded below
style_for() {
  local ext=${1##*.}
  case " $WAYFINDER_SLASH " in *" $ext "*) printf 'jsdoc'; return 0;; esac
  case " $WAYFINDER_HASH " in *" $ext "*) printf 'hash'; return 0;; esac
  printf ''
}

# a reference that only resolves once this repo is symlinked into a host project; the same two
# lists todo.sh keeps, since both tools answer "is this path missing or just elsewhere"
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
    .construct/*) return 0;;
    *) return 1;;
  esac
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

# where the wayfinding header ends, so the comment checks start below it; 0 means the file has no
# wayfinder and every comment line is in scope. this used to live in a second sidecar that had to
# reimplement the boundary it did not own, which is the duplication the merge removed
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
# CHECKS: NAMING
#   the filename itself, which is the one convention a reader meets before opening the file
# ==============

# "PascalCase.tsx, camelCase.tsx, camelCase.ts, MatchCase.css, kebab-case.css" — a script can tell
# whether the casing is one of the allowed shapes; it cannot tell a ui component from a logic one,
# so choosing the RIGHT shape stays on the human checklist below
check_naming() {
  local file=$1 base stem ext
  base=$(basename "$file")
  ext=${base##*.}
  case " $MODULE_EXT " in *" $ext "*) ;; *) return 0;; esac
  stem=${base%.*}
  # a dotted stem is a config or a test sibling, which names itself after what it configures
  case "$stem" in *.*) return 0;; esac
  if printf '%s' "$stem" | grep -qE '^[A-Z][A-Za-z0-9]*$'; then return 0; fi
  if printf '%s' "$stem" | grep -qE '^[a-z][A-Za-z0-9]*$'; then return 0; fi
  warn "$file" 1 naming "'$stem' is neither PascalCase nor camelCase; see the Naming convention"
}

# ==============
# CHECKS: WAYFINDER
#   each takes a file path and a style, and appends findings
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
check_header_width() {
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
check_header_casing() {
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

# ==============
# CHECKS: MODULES
#   the import block's order, which is a js/ts convention and nothing else's
# ==============

# "external packages, then internal @/aliased code" — a script can see that ordering inverted; it
# cannot judge the finer grouping inside each band, which stays on the human checklist
check_modules() {
  local file=$1 ext lineno line seen_internal=0
  ext=${file##*.}
  case " $MODULE_EXT " in *" $ext "*) ;; *) return 0;; esac
  while IFS=$'\t' read -r lineno line; do
    case "$line" in
      *"from \"@/"*|*"from '@/"*) seen_internal=1; continue;;
      *"from \"."*|*"from '."*) continue;;
    esac
    # a bare package specifier after an aliased one inverts the two bands
    if [ "$seen_internal" -eq 1 ]; then
      warn "$file" "$lineno" module_order "external import below an @/ import; externals come first"
      return 0
    fi
  done < <(grep -nE '^[[:space:]]*import[[:space:]]' "$file" 2>/dev/null | sed 's/:/\t/' || true)
}

# ==============
# CHECKS: COMMENTS
#   each takes a file path, a marker and where the wayfinder ended
# ==============

# "`lines` carry a single clause, capped at 100 characters, and never wrap"
check_comment_width() {
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
check_comment_casing() {
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

# "`lines` carry a single clause" — the same comma-chain smell log.sh reports
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

# "#1: use numbered citations" paired with a "(see #1)" pointer; the pair holds only when both do
# a file defining no note opts out, which keeps a github ref like (see #127) out of this check
check_citations() {
  local file=$1 style=$2 lineno line text number defined="" highest=0 expected=1 refs ref hit
  while IFS=$'\t' read -r lineno line; do
    text=$(content_of "$line")
    # notes nest under a NOTES: heading in the template, so the indent is part of the shape
    number=$(printf '%s' "$text" | sed -n 's/^[[:space:]]*-\{0,1\}[[:space:]]*#\([0-9]\{1,\}\):.*/\1/p')
    if [ -z "$number" ]; then continue; fi
    if [ "$number" -ne "$expected" ]; then
      err "$file" "$lineno" citation_numbering "note #$number where #$expected was expected"
    fi
    expected=$((number + 1))
    defined="$defined $number"
    if [ "$number" -gt "$highest" ]; then highest=$number; fi
  done < <(block_lines "$file" "$style")
  if [ -z "$defined" ]; then return 0; fi

  refs=$({ grep -oE 'see #[0-9]+' "$file" || true; } | grep -oE '[0-9]+' | sort -un || true)

  # only a ref inside the note range is judged; a larger number is an issue or a pr, never a note
  for ref in $refs; do
    if [ "$ref" -gt "$highest" ]; then continue; fi
    case " $defined " in *" $ref "*) continue;; esac
    hit=$({ grep -nE "see #$ref\b" "$file" || true; } | head -n 1 | cut -d: -f1)
    err "$file" "${hit:-1}" citation_unresolved "(see #$ref) resolves to no note in the wayfinder"
  done

  for number in $defined; do
    if printf '%s\n' "$refs" | grep -qx "$number"; then continue; fi
    hit=$({ grep -nE "^[^a-zA-Z0-9]*#$number:" "$file" || true; } | head -n 1 | cut -d: -f1)
    warn "$file" "${hit:-1}" citation_orphan "note #$number: dead weight, or a missing (see #$number)"
  done
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
WAYFINDER_SCANNED=0
# an argument filtered down to nothing is a legitimate run, so the empty array expands to nothing
# rather than tripping set -u; bash 3.2 treats a bare "${FILES[@]}" here as an unbound variable
for file in ${FILES[@]+"${FILES[@]}"}; do
  check_naming  "$file"
  check_modules "$file"

  # the header family runs only on the narrow list, since nothing else carries a wayfinder
  STYLE=$(style_for "$file")
  if [ -n "$STYLE" ]; then
    WAYFINDER_SCANNED=$((WAYFINDER_SCANNED + 1))
    # every remaining header check reads the block, so a file without one has nothing to say
    if check_present "$file" "$STYLE"; then
      check_position       "$file" "$STYLE"
      check_tags           "$file" "$STYLE"
      check_file_tag       "$file" "$STYLE"
      check_banner         "$file" "$STYLE"
      check_description    "$file" "$STYLE"
      check_see            "$file" "$STYLE"
      check_header_width   "$file" "$STYLE"
      check_header_casing  "$file" "$STYLE"
      check_citations      "$file" "$STYLE"
    fi
  fi

  # the comment family runs on the wide list, so a go file is graded here and never above
  MARKER=$(marker_for "$file")
  if [ -n "$MARKER" ]; then
    SKIP=$(wayfinder_end "$file" "$MARKER")
    check_comment_width  "$file" "$MARKER" "$SKIP"
    check_comment_casing "$file" "$MARKER" "$SKIP"
    check_clause         "$file" "$MARKER" "$SKIP"
    check_block          "$file" "$MARKER" "$SKIP"
    check_block_comment  "$file" "$MARKER" "$SKIP"
  fi

  scan_secrets "$file"
done

# ==============
# ARTIFACT
#   this skill's own dated artifact, graded here so nothing outside this file decides its shape
#   the shape lives in this skill's SKILL.md and the labels below are what this sidecar emits
# ==============
ARTIFACT_KIND="files"
ARTIFACT_SECTIONS=$'state\nfindings\nresolutions\ntelemetry'
ARTIFACT_LABELS='Naming|Wayfinder|Position|Tags|File Tag|Banner|Wrapped|Description|See Empty|See Unresolved|Module Order|Spacing|Width|Casing|Period|Clause|Block|Block Comment|Commented Code|Scrub'
ARTIFACT_MAX_WIDTH=100

# this sidecar reports "file|line|category|detail", so the checks pass straight through
artifact_err()  { err "$1" "$2" "$3" "$4"; }
artifact_warn() { warn "$1" "$2" "$3" "$4"; }

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
  local expected=1 previous='' count=0 found=0 fixed=0 lineno text infence=0
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
    # heading to the file, so a settings entry in the git file is caught rather than merged
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
        artifact_err "$rel" "$lineno" finding_shape 'findings read "- **Label** — what is wrong, and on what"'
        continue
      fi
      label=$(printf '%s' "$text" | sed -n 's/^- \*\*\([^*]*\)\*\*.*/\1/p')
      if ! printf '%s' "$label" | grep -qE "^($ARTIFACT_LABELS)\$"; then
        artifact_warn "$rel" "$lineno" finding_label "'$label' is not a label this sidecar emits"
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
      artifact_err "$rel" "$start" telemetry "telemetry holds the raw sidecar output, never blank"
    elif [ "$(printf '%s' "$body" | grep -c '^```' || true)" -lt 2 ]; then
      artifact_warn "$rel" "$start" telemetry "fence the raw output, so a reader can tell it from prose"
    fi
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

if [ "$SCOPED" -eq 0 ]; then check_artifact ".construct/retardify/file"; fi

# ==============
# TELEMETRY
# ==============
ERRORS=$(grep -c '^ERROR|' "$FINDINGS" || true)
WARNINGS=$(grep -c '^WARN|' "$FINDINGS" || true)
SECRETS=$(grep -c '|secret|' "$FINDINGS" || true)

# audit: one file per day per kind, so two runs on the same day never interleave one file
# reported, never created: the sidecar names the path and the count, the agent writes the entry
AUDIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
TODAYS_AUDIT=".construct/retardify/file/$(date +%Y-%m-%d).md"
if [ -f "$AUDIT_ROOT/$TODAYS_AUDIT" ];
then AUDIT_COUNT=$(grep -c '^## Files Audit #' "$AUDIT_ROOT/$TODAYS_AUDIT" || true)
else AUDIT_COUNT=0; fi
AUDIT_COUNT=${AUDIT_COUNT:-0}

cat <<EOF

=== file.sh sidecar ===
audit_file: $TODAYS_AUDIT
audit_count: $AUDIT_COUNT
next_audit: $((AUDIT_COUNT + 1))
timestamp: $(date '+%Y-%m-%d %H:%M')
template: $TEMPLATE
scanned: ${#FILES[@]} source file(s)
wayfinder_scope: $WAYFINDER_SCANNED eligible for a header
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
- the filename says which of the five shapes it is; a script sees the casing, not the role
- imports group external, then webflow, then internal, then reexported, then exported
- the header says what the file is FOR and where its edges are, never how it works
- every tag reflects the file as it now stands, since a drifted tag misleads worse than none
- @see names what a reader opens next, not every module the file happens to import
- every comment says WHY the code exists, not what it does, unless the code is genuinely hard
- a comment restating the line below it is deleted, since the code already said that
- an unclear line gets refactored for legibility before it gets explained in prose
- a trailing comment is never scanned here, so its shape is on you: `// retry budget — seconds`
- a key that reached a commit is already leaked; rotate it before rewriting anything
========================
EOF

if [ "$ERRORS" -gt 0 ]; then exit 1; fi
if [ "$STRICT" -eq 1 ] && [ "$WARNINGS" -gt 0 ]; then exit 1; fi
exit 0


#!/bin/bash
# ====================================================================
# @file docs.sh - readme shape sidecar: grades one markdown doc's frame
# ====================================================================
# @description
# PAIR
# - sidecar for `/retardify:docs` — grades the readme conventions its SKILL.md states outright
# - the doc carries the conventions and the audit shape; this file carries what a script judges
# - the frame of a markdown doc: title, toc, headings, tables, bullets, links and notes
# - what a script cannot judge stays in the checklist, the same posture code.sh holds
# SCOPE
# - one doc per run, like code.sh; `/retardify:file` never grades markdown, so nothing overlaps
# - fenced content is skipped whole, since a toc tree or a yaml block is content and never prose
# - a `## Notes` section is graded only when present; a doc without one owes nothing to that rule
# TARGET
# - `<path>` names the doc; a leading `@` is shed, since an ide mention arrives as `@README.md`
# - `[text](file:///abs/path#L47:55)` is the ide's link form; the url is taken and the text dropped
# - a bare word with no extension, such as `readme`, resolves to `<word>.md` case-insensitively
# - a leading slash reads as repo-relative first, so `/docs/x.md` and `docs/x.md` name the same file
# - `-` reads the doc from stdin, so pasted text is graded by piping it in rather than retyping it
# RANGE
# - `47:55`, `47-55`, `#L47:55` or `#L47-L55` scope the report to those lines, as a second word
# - the whole doc is still graded, since a toc or an anchor cannot be judged from a slice of it
# - findings outside the range are hidden and counted, so the exit code answers about the slice
# RUN
# - `docs.sh <path> [range]` grades one doc; the one argument may carry both words in one string
# - ERROR breaks a rule the doc states outright; WARN names a smell the doc tolerates
# - `--strict` promotes warnings to errors; exits 1 on any error
# - `--warn` is its inverse: every finding reports and the run exits 0, which is how ci reads it
# - passing both is refused, since one bar has to answer for the exit code
# - `--quick` names no audit file, since a ci runner has no agent to append one
# NOTES
# - #1: the ide's link form carries `[...]`, which an unquoted shell expansion reads as a glob
# - #2: so the doc quotes `$ARGUMENTS` whole, and this file splits the words with globbing off
# - #3: a toc row reads `├─ Label ─── child · child`, one label per h2 or h3, children lowercase
# - #4: a row may list no children when each sub-heading earns a row of its own instead
# - #5: a leading slash on a label and a `parent/` prefix on a child are both shed before comparing
# - #6: a child compares with spaces and hyphens squashed, so `validate-skills` meets its heading
# - #7: fence state is computed once per pass; a fence closes on a delimiter as long as its opener
# - #8: `err` and `warn` drop a leading file argument, since the shared secret scan passes one
# @see plugins/retardify/skills/docs/SKILL.md, plugins/retardify/skills/code/code.sh, plugins/retardify/shared/secrets.sh, plugins/retardify/shared/clean-tmp.sh, README.md, .construct/retardify/docs/

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

# character counts, not byte counts: the toc tree is drawn in box characters that are 3 bytes each
UTF8_LOCALE=$(locale -a 2>/dev/null | grep -iE '^(C|en_US)\.(utf-?8)$' | head -n 1 || true)
if [ -n "$UTF8_LOCALE" ]; then export LC_ALL="$UTF8_LOCALE"; fi

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "fatal: not a git repository" >&2; exit 1; fi
ROOT=$(git rev-parse --show-toplevel)
CALLER_PWD=$(pwd)
cd "$ROOT"

ARTIFACTS=".construct/retardify/docs"
TEMPLATE="plugins/retardify/skills/docs/SKILL.md"

# "a prose line caps at 120 characters"; links are measured by their text, since a url is not read
MAX_WIDTH=120

# "bullets nest two levels; a third is an outline, not a list"
MAX_BULLET_DEPTH=2

# "three prose lines in a row is a paragraph, and a readme reads one clause per line"
MAX_PROSE_RUN=2

# a doc shorter than this owes no table of contents
TOC_MIN_H2=4

# the one argument may carry both words, so it is split here with globbing off (see #2)
set -f
# shellcheck disable=SC2086,SC2048
set -- $*
set +f

STRICT=0
QUICK=0
WARN_ONLY=0
TARGET=""
RANGE=""
EXTRA=0
for arg in "$@"; do
  case "$arg" in
    --strict) STRICT=1;;
    --quick) QUICK=1;;
    --warn) WARN_ONLY=1;;
    -) TARGET="-";;
    -*) echo "fatal: unknown flag $arg" >&2; exit 1;;
    *)
      if [ -z "$TARGET" ]; then TARGET="$arg"
      elif [ -z "$RANGE" ] && printf '%s' "$arg" | grep -qE '^L?[0-9]+([:-]L?[0-9]+)?$'; then RANGE="$arg"
      else EXTRA=$((EXTRA + 1)); fi;;
  esac
done

# refused rather than ordered by precedence, since a silent winner hides the typo in a ci step
if [ "$STRICT" -eq 1 ] && [ "$WARN_ONLY" -eq 1 ]; then
  echo "fatal: --strict and --warn are opposites; pass one" >&2; exit 1; fi

if [ -z "$TARGET" ]; then
  echo "fatal: /retardify:docs needs a target, as in: /retardify:docs README.md 47:55" >&2; exit 1; fi

# ==============
# TARGET
# ==============
# the ide's link form hands over a url, and a `#L` suffix on that url is a range (see #1)
TARGET=${TARGET#@}
case "$TARGET" in
  \[*\]\(*\)) TARGET=${TARGET#*\](}; TARGET=${TARGET%)};;
esac
TARGET=${TARGET#file://}
case "$TARGET" in
  *'#L'*) if [ -z "$RANGE" ]; then RANGE=${TARGET##*#L}; fi; TARGET=${TARGET%%#L*};;
esac
TARGET=${TARGET#@}

# a range reads `47:55` or `47-55` or a single `47`; the ide's `L` prefix is shed first
FROM=0
TO=0
if [ -n "$RANGE" ]; then
  RANGE=$(printf '%s' "$RANGE" | tr -d 'L' | tr ':' '-')
  FROM=${RANGE%%-*}
  TO=${RANGE##*-}
  if [ "$FROM" -gt "$TO" ]; then
    echo "fatal: range $FROM-$TO runs backwards" >&2; exit 1; fi
fi

# repo-local scratch: the sandbox denies writes outside cwd, and macos mktemp ignores TMPDIR
TMPROOT="$ROOT/tmp"
mkdir -p "$TMPROOT"
FINDINGS=$(mktemp "$TMPROOT/docs-findings.XXXXXX")
HEADINGS=$(mktemp "$TMPROOT/docs-headings.XXXXXX")
SLUGS=$(mktemp "$TMPROOT/docs-slugs.XXXXXX")
SHOWN=$(mktemp "$TMPROOT/docs-shown.XXXXXX")
cleanup() { st=$?; if [ "$st" -eq 0 ]; then bash "$ROOT/plugins/retardify/shared/clean-tmp.sh" docs; fi; }
trap cleanup EXIT

# `readme` names README.md in whichever case the repo spelled it, from where the user stood first
resolve_bare_name() {
  local word=$1 dir found
  for dir in "$CALLER_PWD" "$ROOT"; do
    found=$(find "$dir" -maxdepth 1 -iname "$word.md" -type f 2>/dev/null | head -n 1 || true)
    if [ -n "$found" ]; then printf '%s' "$found"; return 0; fi
  done
  printf '%s' "$word"
}

# stdin lands in scratch, so every check below reads one file the same way
SOURCE="stdin"
if [ "$TARGET" = "-" ]; then
  FILE=$(mktemp "$TMPROOT/docs-stdin.XXXXXX")
  cat > "$FILE"
  if [ ! -s "$FILE" ]; then echo "fatal: nothing arrived on stdin" >&2; exit 1; fi
else
  SOURCE="path"
  # a relative path is read from where the user stood first, then from the repo root
  if [ ! -e "$TARGET" ] && [ -e "$CALLER_PWD/$TARGET" ]; then TARGET="$CALLER_PWD/$TARGET"; fi
  TARGET=${TARGET#./}
  # a leading slash reads as repo-relative first, since the doc's own example writes /folder/file.md
  case "$TARGET" in
    /*) if [ ! -f "$TARGET" ] && [ -e "${TARGET#/}" ]; then TARGET="${TARGET#/}"; fi;;
  esac
  case "$TARGET" in
    */*|*.*) ;;
    *) if [ ! -e "$TARGET" ]; then TARGET=$(resolve_bare_name "$TARGET"); fi;;
  esac
  FILE="$TARGET"
fi

if [ -d "$FILE" ]; then
  echo "fatal: '$FILE' is a directory; this sidecar grades exactly one markdown doc" >&2; exit 1; fi
if [ ! -f "$FILE" ] && [ "$EXTRA" -gt 0 ]; then
  echo "fatal: no such file: $TARGET, and $EXTRA more word(s) followed it" >&2
  echo "paste: detected — pipe the text in with 'docs.sh -' rather than passing it as words" >&2
  exit 1
fi
if [ ! -f "$FILE" ]; then
  echo "fatal: no such file: $TARGET" >&2; exit 1; fi
case "$FILE" in
  *.md|*.MD|*.markdown) ;;
  *) if [ "$SOURCE" = "path" ]; then echo "fatal: '$FILE' is not a markdown doc" >&2; exit 1; fi;;
esac

# findings name the doc repo-relative, and the stdin copy is scratch, so it is named for its source
LABEL=${FILE#"$ROOT"/}
if [ "$SOURCE" = "stdin" ]; then LABEL="stdin"; fi

# findings collect as "SEV|line|category|detail", where line 0 names a whole-doc finding (see #8)
err()  { if [ $# -eq 4 ]; then shift; fi; printf 'ERROR|%s|%s|%s\n' "$1" "$2" "$3" >> "$FINDINGS"; }
warn() { if [ $# -eq 4 ]; then shift; fi; printf 'WARN|%s|%s|%s\n' "$1" "$2" "$3" >> "$FINDINGS"; }

# every line as `N\tF\tTEXT`, where F is 1 inside a fence or on its delimiters (see #7)
lines() {
  awk '{
    text = $0; sub(/^[[:space:]]+/, "", text)
    if (text ~ /^```/) {
      n = 0; while (substr(text, n + 1, 1) == "`") n++
      if (!fence) { fence = n; print NR "\t1\t" $0; next }
      if (n >= fence) { fence = 0; print NR "\t1\t" $0; next }
    }
    print NR "\t" (fence ? 1 : 0) "\t" $0
  }' "$FILE"
}

# the headings outside fences, as `N\tLEVEL\tTEXT\tGAP`, where GAP is 1 when a blank line sits above
awk -F'\t' '
  $2 == 0 && $3 ~ /^#{1,6} / {
    n = 0; while (substr($3, n + 1, 1) == "#") n++
    print $1 "\t" n "\t" substr($3, n + 2) "\t" (prev == "" ? 1 : 0)
  }
  { prev = $3 }' <(lines) > "$HEADINGS"

# github's anchor: lowercase, punctuation shed, spaces to hyphens; computed once for every heading
awk -F'\t' '{ print $3 }' "$HEADINGS" \
  | tr '[:upper:]' '[:lower:]' | sed -e 's/[^a-z0-9 -]//g' -e 's/ /-/g' > "$SLUGS"

# a label and a heading compare lowercase with a leading slash shed (see #5)
norm() {
  local text=$1
  text=${text#/}
  printf '%s' "$text" | tr '[:upper:]' '[:lower:]'
}

# a children list compares with its spaces and hyphens squashed (see #6)
squash() {
  printf '%s' "$1" | tr -d ' -'
}

# a code span quotes a pattern rather than using it, so it is shed before a pointer is looked for
shed_spans() {
  printf '%s' "$1" | sed -E 's/`[^`]*`//g'
}

# a link's url is not read, so the width of a line is its text with every `](url)` shed
visible_width() {
  local text
  text=$(printf '%s' "$1" | sed -E 's/\]\([^)]*\)/]/g')
  printf '%s' "${#text}"
}

# the first non-blank line after a given one, so an epigraph check can see past a blank
next_content() {
  awk -v start="$1" 'NR > start && $0 !~ /^[[:space:]]*$/ { print; exit }' "$FILE"
}

# ==============
# CHECKS
#   each appends findings; to add one, write a function and list it in the run block below
# ==============

# "a fence that never closes swallows every heading after it"
check_fences() {
  local open
  open=$(awk '{
    text = $0; sub(/^[[:space:]]+/, "", text)
    if (text !~ /^```/) next
    n = 0; while (substr(text, n + 1, 1) == "`") n++
    if (!fence) { fence = n; at = NR } else if (n >= fence) fence = 0
  } END { print (fence ? at : 0) }' "$FILE")
  if [ "$open" -gt 0 ]; then
    err "$open" fence_unclosed "a fence opens here and nothing closes it"
  fi
}

# "line 1 is the one h1, and line 2 is a bold one-line subtitle"
check_title() {
  local first second extra
  first=$(sed -n '1p' "$FILE")
  second=$(sed -n '2p' "$FILE")
  case "$first" in
    "# "*) ;;
    *) err 1 title "line 1 is not an h1; a readme opens on '# Name: Tagline'";;
  esac
  extra=$(awk -F'\t' '$2 == 1 && $1 > 1 { print $1; exit }' "$HEADINGS")
  if [ -n "$extra" ]; then
    err "$extra" title "a second h1; a doc has one title"
  fi
  case "$second" in
    '**'*'**') ;;
    *) warn 2 subtitle "line 2 is not a bold one-line subtitle under the title";;
  esac
}

# "a heading steps down one level at a time, with a blank line above it"
check_headings() {
  local n level text gap prev_level=0
  while IFS=$'\t' read -r n level text gap; do
    [ -n "$n" ] || continue
    if [ "$prev_level" -gt 0 ] && [ "$level" -gt $((prev_level + 1)) ]; then
      err "$n" heading_skip "h$level under an h$prev_level; headings step one level at a time"
    fi
    prev_level=$level
    if [ "$n" -gt 1 ] && [ "$gap" -eq 0 ]; then
      warn "$n" heading_gap "no blank line above this heading"
    fi
  done < "$HEADINGS"
}

# "two headings with the same text collide on one anchor, so every link lands on the first"
check_heading_dupes() {
  local n first text
  while IFS=$'\t' read -r n first text; do
    [ -n "$n" ] || continue
    warn "$n" heading_dup "'$text' repeats line $first, so a #anchor to it lands on the first"
  done < <(awk -F'\t' '{
    key = tolower($3)
    if (key in seen) print $1 "\t" seen[key] "\t" $3; else seen[key] = $1
  }' "$HEADINGS")
}

# "an h2 or h3 that opens straight onto content carries a one-line `>` epigraph first"
check_epigraph() {
  local n level text gap next
  while IFS=$'\t' read -r n level text gap; do
    [ -n "$n" ] || continue
    [ "$level" -eq 2 ] || [ "$level" -eq 3 ] || continue
    next=$(next_content "$n")
    case "$next" in
      '>'*|'#'*|'') ;;
      *) warn "$n" epigraph "'$text' opens onto content with no '> ' line saying what it covers";;
    esac
  done < "$HEADINGS"
}

# the headings one level under a labelled h2 or h3, lowercase and joined with ` · ` (see #5)
toc_children_of() {
  awk -F'\t' -v want="$(norm "$1")" '
    function shed(text, parent) {
      sub(/^\//, "", text)
      if (index(text, parent "/") == 1) text = substr(text, length(parent) + 2)
      return tolower(text)
    }
    !inside && ($2 == 2 || $2 == 3) && shed($3, "") == want { inside = 1; level = $2; next }
    inside && $2 <= level { exit }
    inside && $2 == level + 1 { out = out (out ? " · " : "") shed($3, want) }
    END { print out }' "$HEADINGS"
}

# a toc row names a heading when the row's label matches it lowercase, slash shed
toc_has_row() {
  awk -F'\t' -v want="$(norm "$1")" '
    { label = $2; sub(/^\//, "", label) }
    tolower(label) == want || index(tolower(label), want) == 1 { found = 1 }
    END { exit !found }' "$2"
}

# "the toc is a fenced tree naming every h2 and the h3s under it; a stale one misdirects" (see #3)
check_toc() {
  local toc_start toc_end h2_count rows n label children level text wanted sorted_have sorted_want
  h2_count=$(awk -F'\t' '$2 == 2' "$HEADINGS" | wc -l | tr -d ' ')
  toc_start=$(grep -nE '^TABLE OF CONTENTS[[:space:]]*$' "$FILE" | head -n 1 | cut -d: -f1 || true)
  if [ -z "$toc_start" ] && [ "$h2_count" -ge "$TOC_MIN_H2" ]; then
    warn 0 toc_missing "$h2_count h2 sections and no fenced TABLE OF CONTENTS tree"
  fi
  [ -n "$toc_start" ] || return 0
  toc_end=$(awk -v start="$toc_start" 'NR > start && /^```/ { print NR; exit }' "$FILE")
  toc_end=${toc_end:-$toc_start}
  # each row is `N\tLABEL\tCHILDREN`; the tree glyphs and the dash padding are decoration
  rows=$(mktemp "$TMPROOT/docs-toc.XXXXXX")
  sed -n "$((toc_start + 1)),$((toc_end - 1))p" "$FILE" | awk -v start="$toc_start" '{
    line = $0; children = ""
    sub(/^[[:space:]]*[├└│]+[─ ]*/, "", line)
    if (match(line, /[[:space:]]+─+[[:space:]]+/)) {
      children = substr(line, RSTART + RLENGTH); line = substr(line, 1, RSTART - 1) }
    print (NR + start) "\t" line "\t" children
  }' > "$rows"
  # every row names a real h2 or h3, and every h2 has a row
  while IFS=$'\t' read -r n label children; do
    [ -n "$label" ] || continue
    if ! awk -F'\t' -v want="$(norm "$label")" '
        { text = $3; sub(/^\//, "", text) }
        ($2 == 2 || $2 == 3) && tolower(text) == want { found = 1 }
        END { exit !found }' "$HEADINGS"; then
      err "$n" toc_stale "toc row '$label' names no h2 or h3 in this doc"
    fi
  done < "$rows"
  while IFS=$'\t' read -r n level text gap; do
    [ -n "$n" ] || continue
    [ "$level" -eq 2 ] || continue
    if ! toc_has_row "$text" "$rows"; then
      err "$n" toc_missing_entry "'$text' is an h2 with no toc row"
    fi
  done < "$HEADINGS"
  # a row's children are the headings one level below, or those headings own rows (see #4)
  while IFS=$'\t' read -r n label children; do
    [ -n "$label" ] || continue
    wanted=$(toc_children_of "$label")
    [ -n "$wanted" ] || continue
    if [ -z "$children" ]; then
      toc_has_row "${wanted%% · *}" "$rows" && continue
      warn "$n" toc_children "'$label' lists no children and its sub-headings have no rows of their own"
      continue
    fi
    children=$(printf '%s' "$children" | tr '[:upper:]' '[:lower:]')
    [ "$(squash "$children")" != "$(squash "$wanted")" ] || continue
    sorted_have=$(squash "$children" | tr '·' '\n' | sort | tr '\n' ' ')
    sorted_want=$(squash "$wanted" | tr '·' '\n' | sort | tr '\n' ' ')
    if [ "$sorted_have" = "$sorted_want" ]; then
      warn "$n" toc_order "'$label' children run in a different order than the headings do"
    else
      warn "$n" toc_children "'$label' children read '$children'; the headings read '$wanted'"
    fi
  done < "$rows"
}

# one link target on one line: an anchor lands on a heading slug, a relative path on a file
check_link_target() {
  local n=$1 target=$2 base
  case "$target" in
    '#'*)
      grep -qxF -- "${target#\#}" "$SLUGS" && return 0
      err "$n" anchor_unresolved "'$target' matches no heading slug in this doc";;
    http://*|https://*|mailto:*|file://*) ;;
    *)
      base=${target%%#*}
      [ -n "$base" ] || return 0
      [ -e "$base" ] || [ -e "$(dirname "$FILE")/$base" ] && return 0
      err "$n" link_unresolved "'$target' resolves to no file from the doc or the repo root";;
  esac
}

# "every `](#anchor)` lands on a heading in this doc, and every relative link on a file"
check_links() {
  local n flag text target
  while IFS=$'\t' read -r n flag text; do
    [ "$flag" -eq 0 ] || continue
    case "$text" in *']('*) ;; *) continue;; esac
    while IFS= read -r target; do
      [ -n "$target" ] || continue
      check_link_target "$n" "$target"
    done < <(shed_spans "$text" | grep -oE '\]\([^)[:space:]]+\)' | sed -e 's/^](//' -e 's/)$//' || true)
  done < <(lines)
}

# "a table sits under a blank line", judged once per table on its header row
check_table_gap() {
  local above
  [ "$1" -gt 1 ] || return 0
  above=$(sed -n "$(($1 - 1))p" "$FILE")
  [ -n "$above" ] || return 0
  warn "$1" table_gap "no blank line above this table"
}

# "every table row carries the header's column count, and its pipes line up"
check_tables() {
  local n flag text cols width in_table=0 head_cols=0 head_width=0 head_line=0
  while IFS=$'\t' read -r n flag text; do
    if [ "$flag" -eq 1 ] || [ "${text:0:1}" != '|' ]; then
      in_table=0; continue
    fi
    cols=$(printf '%s' "$text" | tr -cd '|' | wc -c | tr -d ' ')
    width=${#text}
    if [ "$in_table" -eq 0 ]; then
      in_table=1; head_cols=$cols; head_width=$width; head_line=$n
      check_table_gap "$n"
      continue
    fi
    if [ "$cols" -ne "$head_cols" ]; then
      err "$n" table_cols "$cols pipes where the header at line $head_line has $head_cols"
    elif [ "$width" -ne "$head_width" ]; then
      warn "$n" table_align "$width chars wide where the header is $head_width; pad the cells"
    fi
  done < <(lines)
}

# "hyphen bullets, two levels deep at most"
check_bullets() {
  local n flag text indent body depth
  while IFS=$'\t' read -r n flag text; do
    [ "$flag" -eq 0 ] || continue
    indent=${text%%[![:space:]]*}
    body=${text#"$indent"}
    case "$body" in
      '* '*|'+ '*) err "$n" bullet_marker "a '${body:0:1}' bullet; this doc's bullets are hyphens"; continue;;
      '- '*) ;;
      *) continue;;
    esac
    depth=$(( ${#indent} / 2 + 1 ))
    [ "$depth" -gt "$MAX_BULLET_DEPTH" ] || continue
    warn "$n" bullet_depth "a level $depth bullet; past $MAX_BULLET_DEPTH levels a list is an outline"
  done < <(lines)
}

# "bold opens a line as a label or carries the subtitle; mid-sentence bold is shouting"
check_bold() {
  local n flag text stripped
  while IFS=$'\t' read -r n flag text; do
    [ "$flag" -eq 0 ] || continue
    [ "$n" -gt 2 ] || continue
    case "$text" in *'**'*'**'*) ;; *) continue;; esac
    stripped=$(printf '%s' "$text" | sed -E 's/`[^`]*`//g')
    stripped=${stripped#"${stripped%%[![:space:]]*}"}
    stripped=${stripped#- }
    stripped=${stripped#> }
    case "$stripped" in
      '**'*|'|'*) ;;
      *'**'*'**'*) warn "$n" bold_inline "bold inside a sentence; bold opens a line as a label or not at all";;
    esac
  done < <(lines)
}

# a line that is structure rather than prose: a heading or a bullet or a quote or a table row
is_structure() {
  local text=$1 first
  first=${text#"${text%%[![:space:]]*}"}
  case "$first" in
    ''|'#'*|'- '*|'* '*|'>'*|'|'*|'<'*|'`'*|'!['*|'['*) return 0;;
    [0-9]*'. '*) return 0;;
  esac
  return 1
}

# "a readme reads one clause per line; three plain lines in a row is a paragraph"
check_prose() {
  local n flag text run=0 start=0
  while IFS=$'\t' read -r n flag text; do
    if [ "$flag" -eq 1 ] || is_structure "$text"; then
      if [ "$run" -gt "$MAX_PROSE_RUN" ]; then
        warn "$start" paragraph "$run plain lines in a row; a readme reads one clause per line"
      fi
      run=0; continue
    fi
    if [ "$run" -eq 0 ]; then start=$n; fi
    run=$((run + 1))
  done < <(lines)
  if [ "$run" -gt "$MAX_PROSE_RUN" ]; then
    warn "$start" paragraph "$run plain lines in a row; a readme reads one clause per line"
  fi
}

# "a line caps at 120 visible characters; a long clause is a shorter one, never a wrapped one"
check_width() {
  local n flag text width
  while IFS=$'\t' read -r n flag text; do
    [ "$flag" -eq 0 ] || continue
    [ "${text:0:1}" != '|' ] || continue
    [ "${#text}" -gt "$MAX_WIDTH" ] || continue
    width=$(visible_width "$text")
    [ "$width" -gt "$MAX_WIDTH" ] || continue
    warn "$n" width "$width visible chars; the cap is $MAX_WIDTH"
  done < <(lines)
}

# "one blank line between blocks, never two"; a trailing space is invisible drift
check_blanks() {
  local n flag text run=0
  while IFS=$'\t' read -r n flag text; do
    if [ -z "$text" ]; then
      run=$((run + 1))
      if [ "$run" -eq 2 ]; then
        warn "$n" blank_run "two blank lines; one separates a block, two separate nothing"
      fi
      continue
    fi
    run=0
    [ "$flag" -eq 0 ] || continue
    case "$text" in
      *' '|*$'\t') warn "$n" trailing "trailing whitespace";;
    esac
  done < <(lines)
}

# "no emoji; the readme is read in a terminal as often as on github"
check_emoji() {
  local n flag text
  local hi=$'\xf0\x9f' misc=$'\xe2\x9c' mark=$'\xe2\x9d' sign=$'\xe2\x9a'
  while IFS=$'\t' read -r n flag text; do
    [ "$flag" -eq 0 ] || continue
    case "$text" in
      *"$hi"*|*"$misc"*|*"$mark"*|*"$sign"*) warn "$n" emoji "an emoji; the doc reads in a terminal too";;
    esac
  done < <(lines)
}

# every `- #N:` note between two lines, numbered from 1 without a gap, and each pointed at
check_note_lines() {
  local notes_start=$1 notes_end=$2 n flag text num prev=0
  while IFS=$'\t' read -r n flag text; do
    [ "$n" -gt "$notes_start" ] && [ "$n" -lt "$notes_end" ] || continue
    [ "$flag" -eq 0 ] || continue
    case "$text" in '- #'*) ;; *) continue;; esac
    num=$(printf '%s' "$text" | sed -nE 's/^- #([0-9]+):.*/\1/p')
    if [ -z "$num" ]; then
      warn "$n" note_shape "a note reads '- #N: clause', with the colon"; continue
    fi
    if [ "$num" -ne $((prev + 1)) ]; then
      warn "$n" note_numbering "note #$num follows #$prev; notes climb by one"
    fi
    prev=$num
    grep -qE "\(see #$num\)" "$FILE" && continue
    warn "$n" note_orphan "nothing in the body points at #$num"
  done < <(lines)
}

# every `(see #N)` pointer lands on a note that exists between two lines
check_note_pointers() {
  local notes_start=$1 notes_end=$2 n flag text num
  while IFS=$'\t' read -r n flag text; do
    [ "$flag" -eq 0 ] || continue
    case "$text" in *'(see #'*) ;; *) continue;; esac
    while IFS= read -r num; do
      [ -n "$num" ] || continue
      sed -n "$notes_start,${notes_end}p" "$FILE" | grep -qE "^- #$num:" && continue
      err "$n" note_unresolved "'(see #$num)' points at a note '## Notes' does not hold"
    done < <(shed_spans "$text" | grep -oE '\(see #[0-9]+\)' | tr -cd '0-9\n' || true)
  done < <(lines)
}

# the first unfenced line pointing at a note, with code spans shed, or nothing
first_pointer() {
  local n flag text
  while IFS=$'\t' read -r n flag text; do
    [ "$flag" -eq 0 ] || continue
    case "$text" in *'(see #'*) ;; *) continue;; esac
    if shed_spans "$text" | grep -qE '\(see #[0-9]+\)'; then printf '%s' "$n"; return 0; fi
  done < <(lines)
}

# "the body stays legible by pointing at a note; `(see #N)` resolves to `- #N:` under `## Notes`"
check_notes() {
  local notes_start notes_end last_h2 pointer
  notes_start=$(awk -F'\t' '$2 == 2 && tolower($3) == "notes" { print $1; exit }' "$HEADINGS")
  if [ -z "$notes_start" ]; then
    pointer=$(first_pointer)
    [ -n "$pointer" ] || return 0
    err "$pointer" note_unresolved "a '(see #N)' pointer and no '## Notes' section to land on"
    return 0
  fi
  last_h2=$(awk -F'\t' '$2 == 2 { n = $1 } END { print n }' "$HEADINGS")
  if [ "$notes_start" != "$last_h2" ]; then
    warn "$notes_start" notes_position "'## Notes' is not the last h2; the notes close the doc"
  fi
  notes_end=$(awk -F'\t' -v start="$notes_start" '$1 > start && $2 <= 2 { print $1; exit }' "$HEADINGS")
  notes_end=${notes_end:-$(($(wc -l < "$FILE") + 1))}
  check_note_lines "$notes_start" "$notes_end"
  check_note_pointers "$notes_start" "$notes_end"
}

# --- run list (add new checks here) ---
check_fences
check_title
check_headings
check_heading_dupes
check_epigraph
check_toc
check_links
check_tables
check_bullets
check_bold
check_prose
check_width
check_blanks
check_emoji
check_notes
scan_secrets "$FILE"

# ==============
# TELEMETRY
# ==============
LINES=$(wc -l < "$FILE" | tr -d ' ')
H2_COUNT=$(awk -F'\t' '$2 == 2' "$HEADINGS" | wc -l | tr -d ' ')
H3_COUNT=$(awk -F'\t' '$2 == 3' "$HEADINGS" | wc -l | tr -d ' ')
TABLE_COUNT=$(lines | awk -F'\t' '
  $2 == 0 && $3 ~ /^\|/ { if (!in_t) t++; in_t = 1; next }
  { in_t = 0 }
  END { print t + 0 }')

# a range run answers about those lines; whole-doc findings at line 0 stay, the rest are hidden
if [ "$TO" -gt 0 ]; then
  awk -F'|' -v from="$FROM" -v to="$TO" '$2 == 0 || ($2 >= from && $2 <= to)' "$FINDINGS" > "$SHOWN"
else
  cp "$FINDINGS" "$SHOWN"
fi
HIDDEN=$(( $(wc -l < "$FINDINGS") - $(wc -l < "$SHOWN") ))
ERRORS=$(grep -c '^ERROR|' "$SHOWN" || true)
WARNINGS=$(grep -c '^WARN|' "$SHOWN" || true)
SECRETS=$(grep -c '|secret|' "$SHOWN" || true)

# the audit is one file per day, reported here and appended by the agent in the doc's shape
TODAYS_AUDIT="$ARTIFACTS/$(date +%Y-%m-%d).md"
if [ -f "$TODAYS_AUDIT" ];
then AUDIT_COUNT=$(grep -c '^## Docs Audit #' "$TODAYS_AUDIT" || true)
else AUDIT_COUNT=0; fi
AUDIT_COUNT=${AUDIT_COUNT:-0}

# a ci runner has no agent to append an audit, so quick names none and the doc skips that step
if [ "$QUICK" -eq 1 ];
then MODE="quick — report inline, write nothing"; AUDIT_FILE=none
else MODE="audit — append to audit_file"; AUDIT_FILE=$TODAYS_AUDIT; fi

# the bar the exit code answers to, printed so a ci log says which one this run was held to
if [ "$STRICT" -eq 1 ]; then SEVERITY="strict — a warning fails the run"
elif [ "$WARN_ONLY" -eq 1 ]; then SEVERITY="warn — every finding reports, nothing fails the run"
else SEVERITY="default — an error fails the run, a warning does not"; fi

if [ "$TO" -gt 0 ]; then SCOPE="lines $FROM-$TO, $HIDDEN finding(s) outside it hidden"
else SCOPE="whole doc"; fi

cat <<EOF

=== docs.sh sidecar ===
file: $LABEL
source: $SOURCE
scope: $SCOPE
mode: $MODE
severity: $SEVERITY
audit_file: $AUDIT_FILE
audit_count: $AUDIT_COUNT
next_audit: $((AUDIT_COUNT + 1))
timestamp: $(date '+%Y-%m-%d %H:%M')
template: $TEMPLATE
lines: $LINES
headings: $H2_COUNT h2, $H3_COUNT h3
tables: $TABLE_COUNT
width_cap: $MAX_WIDTH chars
bullet_cap: $MAX_BULLET_DEPTH levels
errors: $ERRORS
warnings: $WARNINGS
secrets: $SECRETS
--- findings ---
EOF

if [ "$ERRORS" -eq 0 ] && [ "$WARNINGS" -eq 0 ]; then
  echo "none — every convention the doc states outright holds"
else
  sort -t'|' -k1,1 -k2,2n "$SHOWN" \
    | awk -F'|' -v f="$LABEL" '{ printf "%-5s %-40s %-18s %s\n", $1, f ":" $2, $3, $4 }'
fi

if [ "$SECRETS" -gt 0 ]; then
  cat <<EOF
--- secrets ---
STOP: $SECRETS unambiguous credential match(es) above
- do NOT truncate or edit anything yet; ask the user which match is real and what to do about it
- a key that already reached a commit is leaked, and truncating the file does not un-leak it
EOF
fi

cat <<'EOF'
--- needs a human (first principles no script can judge) ---
VIBES
- TITLE the h1 names the project and the subtitle says what it is for, in one line each
- TOC every row reads as the section it names, so a reader can navigate from the tree alone
- BREVITY a section past a screen points at a note instead of carrying the detail inline
NOT VIBES
- CONTRADICTION a new line that disagrees with a line already in the doc is an error no script sees
- DRIFT a section shaped unlike its siblings was pasted from somewhere else; reshape it to match
- STALE a claim about behaviour the code no longer has; check the line against the source it names
=======================
EOF

if [ "$WARN_ONLY" -eq 1 ]; then exit 0; fi
if [ "$ERRORS" -gt 0 ]; then exit 1; fi
if [ "$STRICT" -eq 1 ] && [ "$WARNINGS" -gt 0 ]; then exit 1; fi
exit 0

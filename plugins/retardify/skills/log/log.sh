#!/bin/bash
# ==========================================
# @file log.sh - agent log validator sidecar
# ==========================================
# @description
# PAIR
# - sidecar for `logs` — asserts a day's log matches the shape its SKILL.md documents
# - the doc carries threads, notes and prompts; this file carries what a script can judge
# ARTIFACT
# - `.operator/logs/YYYY-MM-DD.md`, one file per day, holding the work and the prompts that drove it
# - gitignored in this repo; host projects decide for themselves whether to track it
# - `sessionstart.sh` creates the day's file and `stop.sh` gates the session on it being written
# - no trigger wraps it: a thread, a note or a synthesis is asked for in plain words
# - a thread groups work by task or topic; notes and prompts append under the thread they belong to
# - notes get absorbed into the thread's prose on synthesis; prompts stay a list and get pruned
# RUN
# - defaults to every file in `.operator/logs/`; pass files or a directory to scope it
# - `--strict` promotes warnings to errors, `--keep` preserves scratch; exits 1 on any error
# - ERROR breaks a rule the doc states outright; WARN names a smell the doc tolerates
# @see plugins/retardify/skills/log/SKILL.md, plugins/operator/hooks/sessionstart.sh, plugins/operator/hooks/stop.sh, .operator/logs/, plugins/retardify/shared/secrets.sh

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
# every em dash in a log is 3 bytes — a byte count would flag lines that are legally under the cap
UTF8_LOCALE=$(locale -a 2>/dev/null | grep -iE '^(C|en_US)\.(utf-?8)$' | head -n 1 || true)
if [ -n "$UTF8_LOCALE" ]; then export LC_ALL="$UTF8_LOCALE"; fi

MAX_WIDTH=100
STRICT=0
KEEP=0
TEMPLATE="plugins/retardify/skills/log/SKILL.md"
ARTIFACTS=".operator/logs"

# the subsections every thread carries, which is the one thing every thread must agree on
EXPECTED_SECTIONS=$'context\nchanges\ninsights\nadvice'

# "`threads` group work by task/topic, limited to 50 lines of prose, prompts excluded"
MAX_PROSE_LINES=50

# the budget the whole design rests on: a thread is bounded, so the readers never truncate. lines
# govern how a thread reads, bytes govern what it costs a session to carry, and the two agree at
# roughly this ratio today. `--budget` prints both for the hooks, which own neither
THREAD_MAX_BYTES=5000
INJECT_THREADS=4

# "`notes` are appended after taskcomplete or every 30 minutes, limited to 5 bullets"
MAX_NOTE_BULLETS=5

# a comma chain is the template's own example of superfluous formatting; three is where a line
# stops being one clause and starts being a list that should have been written as one
MAX_COMMAS=3

# asked by sessionstart and stop on every run, so it answers before any file is opened
if [ "${1:-}" = "--budget" ]; then
  echo "thread_max_bytes: $THREAD_MAX_BYTES"
  echo "inject_threads: $INJECT_THREADS"
  echo "max_prose_lines: $MAX_PROSE_LINES"
  exit 0
fi

LOGS=()
for arg in "$@"; do
  case "$arg" in
    --strict) STRICT=1;;
    --keep) KEEP=1;;
    -h|--help) sed -n '2,11p' "$0"; exit 0;;
    -*) echo "fatal: unknown flag $arg" >&2; exit 1;;
    *) LOGS+=("$arg");;
  esac
done

# no paths given: scan the whole artifact directory, anchored to the repo root so the default
# works from any subdirectory — same posture as the @git* sidecars
if [ ${#LOGS[@]} -eq 0 ]; then
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "fatal: not a git repository, and no paths given" >&2; exit 1; fi
  cd "$(git rev-parse --show-toplevel)"
  if [ ! -d "$ARTIFACTS" ]; then echo "fatal: no $ARTIFACTS/ to scan" >&2; exit 1; fi
  LOGS=("$ARTIFACTS"/*.md)
fi

# a directory argument expands to the logs inside it; the *.md glob is what keeps any
# non-log file stop.sh may leave beside them out
EXPANDED=()
for path in "${LOGS[@]}"; do
  if [ -d "$path" ]; then
    for nested in "$path"/*.md; do [ -f "$nested" ] && EXPANDED+=("$nested"); done
  elif [ -f "$path" ]; then EXPANDED+=("$path")
  else echo "fatal: no such log file: $path" >&2; exit 1; fi
done
LOGS=("${EXPANDED[@]}")

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

# emit "START<TAB>END<TAB>HEADING" per `## ` thread, so every check can scope itself to one thread
entries() {
  awk '
    /^## / { if (start) print start "\t" NR - 1 "\t" heading; start = NR; heading = substr($0, 4); next }
    END { if (start) print start "\t" NR "\t" heading }
  ' "$1"
}

# emit "LINENO<TAB>TEXT" for every line inside one thread's `### <name>` block; any heading closes
# it, so a note or a prompt block never counts as section prose
subsection() {
  awk -v s="$2" -v e="$3" -v want="### $4" '
    NR < s || NR > e { next }
    $0 == want { inside = 1; next }
    /^#+ / { inside = 0 }
    inside { print NR "\t" $0 }
  ' "$1"
}

# emit "START<TAB>END<TAB>HEADING" per `#### ` block inside one thread — the notes and the one
# prompts list, which are appended rather than written, and so drift in their own ways
blocks() {
  awk -v s="$2" -v e="$3" '
    NR < s || NR > e { next }
    /^#### / { if (start) print start "\t" NR - 1 "\t" heading; start = NR; heading = substr($0, 6); next }
    END { if (start) print start "\t" (NR < e ? NR : e) "\t" heading }
  ' "$1"
}

# ==============
# CHECKS
#   each takes a log path and appends findings; to add one, write a function and list it below
#   note there is no tracked check: logs are gitignored here,
#   and host projects decide for themselves
# ==============

# "one log file per day, holding both the work and the prompts that drove it"
check_filename() {
  local file=$1 base dir
  base=$(basename "$file")
  dir=$(dirname "$file")
  if ! printf '%s' "$base" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}\.md$'; then
    err "$file" 1 filename "one log file per day, named YYYY-MM-DD.md"
  fi
  case "$dir" in
    "$ARTIFACTS"|"./$ARTIFACTS"|*"/$ARTIFACTS") ;;
    *) warn "$file" 1 location "logs live in $ARTIFACTS/";;
  esac
}

# `sessionstart.sh` seeds the file with its own path as the h1, so a mismatch means yesterday's log
# was copied forward, which is how one day's threads end up filed under another day
check_header() {
  local file=$1 expected actual
  expected="# $ARTIFACTS/$(basename "$file")"
  actual=$(sed -n '1p' "$file")
  if [ "$actual" != "$expected" ]; then
    err "$file" 1 header "line 1 must read '$expected'"
  fi
}

# "## Thread #1: project - short description", numbered in the order the work happened
check_threads() {
  local file=$1 start end heading number expected=1 count=0
  while IFS=$'\t' read -r start end heading; do
    count=$((count + 1))
    if ! printf '%s' "$heading" | grep -qE '^Thread #[0-9]+: [^ ]+ - .'; then
      err "$file" "$start" thread_heading "threads read '## Thread #N: project - short description'"
      continue
    fi
    number=$(printf '%s' "$heading" | sed -n 's/^Thread #\([0-9]\{1,\}\):.*/\1/p')
    if [ "$number" -ne "$expected" ]; then
      err "$file" "$start" thread_numbering "thread $number where $expected was expected"
    fi
    expected=$((number + 1))
  done < <(entries "$file")
  if [ "$count" -eq 0 ]; then
    warn "$file" 1 empty "seeded, holds no threads yet"
  fi
}

# the four subsections, in the template's order; `insights` and `advice` are the two that get
# skipped when a thread is written in a hurry, and they are the two worth reading later
check_subsections() {
  local file=$1 start end heading actual
  while IFS=$'\t' read -r start end heading; do
    actual=$(awk -v s="$start" -v e="$end" 'NR >= s && NR <= e && /^### / { print substr($0, 5) }' "$file")
    if [ -z "$actual" ]; then
      err "$file" "$start" section_order "no ### subsections; expected $(printf '%s' "$EXPECTED_SECTIONS" | tr '\n' '>' | sed 's/>$//')"
    elif [ "$actual" != "$EXPECTED_SECTIONS" ]; then
      err "$file" "$start" section_order "got $(printf '%s' "$actual" | tr '\n' '>' | sed 's/>$//')"
    fi
  done < <(entries "$file")
}

# "`threads` group work by task/topic, limited to 50 lines of prose, prompts excluded" — over the
# cap means either two topics in one thread, or notes nobody ever synthesized
check_prose() {
  local file=$1 start end heading count bytes
  while IFS=$'\t' read -r start end heading; do
    count=$(awk -v s="$start" -v e="$end" '
      NR < s || NR > e { next }
      /^#### PROMPTS/ { skip = 1; next }
      /^#### / { skip = 0 }
      skip { next }
      /^#+ / { next }
      /^[[:space:]]*$/ { next }
      { n++ }
      END { print n + 0 }
    ' "$file")
    if [ "$count" -gt "$MAX_PROSE_LINES" ]; then
      err "$file" "$start" thread_length "$count lines of prose; the cap is $MAX_PROSE_LINES, so split or synthesize"
    fi
    bytes=$(awk -v s="$start" -v e="$end" 'NR >= s && NR <= e { n += length($0) + 1 } END { print n + 0 }' "$file")
    if [ "$bytes" -gt "$THREAD_MAX_BYTES" ]; then
      err "$file" "$start" thread_bytes "$bytes bytes; the cap is $THREAD_MAX_BYTES, so synthesize this thread"
    fi
  done < <(entries "$file")
}

# "list any work or prs you delivered" — a thread that shipped nothing says so in a line
check_changes() {
  local file=$1 start end heading body
  while IFS=$'\t' read -r start end heading; do
    body=$(subsection "$file" "$start" "$end" changes | cut -f2- | grep -v '^[[:space:]]*$' || true)
    if [ -z "$body" ]; then
      warn "$file" "$start" changes_empty "name what shipped, or say outright that nothing did"
    fi
  done < <(entries "$file")
}

# "group tasks into atomicized buckets, in a sequential, checklist style" — advice is the one
# section anybody acts on later, so its items are checkboxes that can be ticked off
check_advice() {
  local file=$1 start end heading lineno text items
  while IFS=$'\t' read -r start end heading; do
    items=0
    while IFS=$'\t' read -r lineno text; do
      case "$text" in
        *"- [ ] "*|*"- [x] "*) items=$((items + 1)); continue;;
        *"- "*) warn "$file" "$lineno" advice_shape "advice items are checkboxes, so they can be ticked off";;
      esac
    done < <(subsection "$file" "$start" "$end" advice)
    if [ "$items" -eq 0 ]; then
      warn "$file" "$start" advice_empty "list what to pick up next, as checkboxes"
    fi
  done < <(entries "$file")
}

# "#### NOTE: YYYY-MM-DD HH:MM", "a subject: followed by a description", "limited to 5 bullets"
check_notes() {
  local file=$1 tstart tend bstart bend bheading bullets first date
  date=$(basename "$file" .md)
  while IFS=$'\t' read -r tstart tend _; do
    while IFS=$'\t' read -r bstart bend bheading; do
      case "$bheading" in "NOTE"*) ;; *) continue;; esac
      if ! printf '%s' "$bheading" \
        | grep -qE '^NOTE: [0-9]{4}-[0-9]{2}-[0-9]{2} ([01][0-9]|2[0-3]):[0-5][0-9]$'; then
        err "$file" "$bstart" note_heading "notes read '#### NOTE: YYYY-MM-DD HH:MM'"
        continue
      fi
      case "$bheading" in
        "NOTE: $date "*) ;;
        *) err "$file" "$bstart" note_date "note is not dated $date; it belongs in that day's log";;
      esac
      bullets=$(awk -v s="$bstart" -v e="$bend" 'NR > s && NR <= e && /^- /' "$file" | wc -l | tr -d ' ')
      if [ "$bullets" -gt "$MAX_NOTE_BULLETS" ]; then
        err "$file" "$bstart" note_bullets "$bullets bullets; a note is capped at $MAX_NOTE_BULLETS"
      fi
      first=$(awk -v s="$bstart" -v e="$bend" 'NR > s && NR <= e && NF { print; exit }' "$file")
      case "$first" in
        "- "*) warn "$file" "$bstart" note_subject "open with a subject line, then the bullets";;
      esac
    done < <(blocks "$file" "$tstart" "$tend")
  done < <(entries "$file")
}

# "synthesize pending notes when creating a new thread" — a note still sitting in a thread that is
# no longer the live one never got absorbed, and its detail is missing from the prose above it
check_pending_notes() {
  local file=$1 last start end heading bstart bend bheading
  last=$(entries "$file" | tail -n 1 | cut -f1)
  if [ -z "$last" ]; then return 0; fi
  while IFS=$'\t' read -r start end heading; do
    if [ "$start" = "$last" ]; then continue; fi
    while IFS=$'\t' read -r bstart bend bheading; do
      case "$bheading" in "NOTE"*) ;; *) continue;; esac
      warn "$file" "$bstart" note_pending "a closed thread still holds a note; absorb it into the prose"
    done < <(blocks "$file" "$start" "$end")
  done < <(entries "$file")
}

# "`prompts` are appended to the thread they drove, rewritten short, always timestamped" and they
# "stay a list, never becoming prose" — one block per thread, at the bottom of it
check_prompts() {
  local file=$1 tstart tend bstart bend bheading count lineno text
  while IFS=$'\t' read -r tstart tend _; do
    count=0
    while IFS=$'\t' read -r bstart bend bheading; do
      case "$bheading" in
        PROMPTS*) count=$((count + 1));;
        *) if [ "$count" -gt 0 ]; then
             warn "$file" "$bstart" prompts_last "prompts sit at the bottom of the thread they drove"
           fi
           continue;;
      esac
      while IFS=$'\t' read -r lineno text; do
        case "$text" in *[![:space:]]*) ;; *) continue;; esac
        if ! printf '%s' "$text" | grep -qE '^- ([01][0-9]|2[0-3]):[0-5][0-9] .'; then
          err "$file" "$lineno" prompt_shape "prompts read '- HH:MM the rewritten ask', one per line"
        fi
      done < <(awk -v s="$bstart" -v e="$bend" 'NR > s && NR <= e { print NR "\t" $0 }' "$file")
    done < <(blocks "$file" "$tstart" "$tend")
    if [ "$count" -eq 0 ]; then
      warn "$file" "$tstart" prompts_missing "no prompts; the ask belongs next to what came of it"
    elif [ "$count" -gt 1 ]; then
      err "$file" "$tstart" prompts_split "$count prompt blocks; a thread keeps one list"
    fi
  done < <(entries "$file")
}

# "`lines` should contain a single clause/fact/action, limited to 100 characters"
check_width() {
  local file=$1 lineno=0 line
  while IFS= read -r line; do
    lineno=$((lineno + 1))
    if [ ${#line} -gt "$MAX_WIDTH" ]; then
      err "$file" "$lineno" width "${#line} chars; the cap is $MAX_WIDTH"
    fi
  done < "$file"
}

# "minimize comma chains, em dashes, **bold**, and superfluous formatting" — ticks are exempt,
# since a log names files and triggers constantly and quoting them is what keeps it readable
check_formatting() {
  local file=$1 lineno=0 line commas
  while IFS= read -r line; do
    lineno=$((lineno + 1))
    case "$line" in "#"*) continue;; esac
    case "$line" in
      *—*) warn "$file" "$lineno" em_dash "em dash; a comma or a full stop reads cleaner here";;
    esac
    case "$line" in
      *'**'*) warn "$file" "$lineno" bold "bold in a log; the heading already carries the emphasis";;
    esac
    commas=$(printf '%s' "$line" | tr -cd ',' | wc -c | tr -d ' ')
    if [ "$commas" -ge "$MAX_COMMAS" ]; then
      warn "$file" "$lineno" comma_chain "$commas commas; one clause per line reads faster"
    fi
  done < "$file"
}

# scaffolding left in a log reads as fact to whoever picks the thread up tomorrow
check_placeholders() {
  local file=$1 hit token
  while IFS= read -r hit; do
    if [ -z "$hit" ]; then continue; fi
    token=$(printf '%s' "${hit#*:}" \
      | grep -oE 'YYYY-MM-DD|HH:MM|\*example:\*|short description|Repeat the above format' | head -n 1)
    err "$file" "${hit%%:*}" placeholder "template scaffolding survived: $token"
  done < <(grep -nE 'YYYY-MM-DD|HH:MM|\*example:\*|short description|Repeat the above format' "$file" || true)
}


# --- run list (add new checks here) ---
for log in "${LOGS[@]}"; do
  check_filename      "$log"
  check_header        "$log"
  check_threads       "$log"
  check_subsections   "$log"
  check_prose         "$log"
  check_changes       "$log"
  check_advice        "$log"
  check_notes         "$log"
  check_pending_notes "$log"
  check_prompts       "$log"
  check_width         "$log"
  check_formatting    "$log"
  check_placeholders  "$log"
  scan_secrets        "$log"
done

# ==============
# TELEMETRY
# ==============
ERRORS=$(grep -c '^ERROR|' "$FINDINGS" || true)
WARNINGS=$(grep -c '^WARN|' "$FINDINGS" || true)
SECRETS=$(grep -c '|secret|' "$FINDINGS" || true)

cat <<EOF

=== logs.sh sidecar ===
template: $TEMPLATE
scanned: ${#LOGS[@]} log file(s)
width_cap: $MAX_WIDTH chars
prose_cap: $MAX_PROSE_LINES lines per thread
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
- notes are incorporated and deleted; prompts are pruned and rewritten, and stay a list forever
- a prompt that started a new thread belongs to the thread it created, not the one before it
- prune a prompt once it is trivial, redundant, or superseded by the one after it
- keep the prompt that changed direction, dropped a constraint, or corrected a wrong assumption
- rewrite every prompt short; never paste the original wording back in
- focus on outcomes, not the conversation; no play-by-plays
- insights are a brutally honest retrospective, including what went wrong
- err on the side of brevity, and capture only the signals worth reading tomorrow
- a key that reached a commit is already leaked; rotate it before rewriting anything
========================
EOF

if [ "$ERRORS" -gt 0 ]; then exit 1; fi
if [ "$STRICT" -eq 1 ] && [ "$WARNINGS" -gt 0 ]; then exit 1; fi
exit 0

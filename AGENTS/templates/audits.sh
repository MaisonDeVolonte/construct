#!/bin/bash
# ===================================================
# @file audits.sh - audit template validator sidecar
# ===================================================
# @description
# - sidecar for `audits.md` — asserts an audit archive matches the template that documents it
# - one check per machine-checkable rule; every rule needing judgement prints as a human checklist
# - ERROR breaks a rule the template states outright; WARN names a smell the template tolerates
# - defaults to every file in `docs/audits/`; pass files or a directory to scope it
# - `--strict` promotes warnings to errors, `--keep` preserves scratch; exits 1 on any error
# @see AGENTS.md, AGENTS/security/secrets.sh, AGENTS/templates/audits.md, AGENTS/git/gitaudit.md, AGENTS/templates/plans.sh, docs/audits/

set -euo pipefail

# ==============
# PREFLIGHT
# ==============
# the shared scan sits beside this file, not beside the repo being scanned: resolve them before
# anything cds to a repo root, since BASH_SOURCE arrives relative and would follow that cd
SHARED=$(cd "$(dirname "${BASH_SOURCE[0]}")/../security" 2>/dev/null && pwd || true)
if [ ! -f "$SHARED/secrets.sh" ]; then
  echo "fatal: no AGENTS/security/secrets.sh beside this sidecar" >&2; exit 1; fi
# shellcheck source=../security/secrets.sh
. "$SHARED/secrets.sh"

# character counts, not byte counts: bash's ${#var} is multibyte-aware under a utf-8 locale, and
# every em dash in a finding is 3 bytes — a byte count would flag lines that are legally under the cap
UTF8_LOCALE=$(locale -a 2>/dev/null | grep -iE '^(C|en_US)\.(utf-?8)$' | head -n 1 || true)
if [ -n "$UTF8_LOCALE" ]; then export LC_ALL="$UTF8_LOCALE"; fi

MAX_WIDTH=100
STRICT=0
KEEP=0
TEMPLATE="AGENTS/templates/audits.md"
ARTIFACTS="docs/audits"

# the subsections every audit carries, which is the one thing every entry must agree on
EXPECTED_SECTIONS=$'state\nfindings\nresolutions\noutcome'

# the labels `@gitaudit` assigns; the vocabulary can grow, so an unknown label only warns
KNOWN_LABELS='Ghost Branch|Local Clutter|Rebase Absorbed|Conflict Risk|Dirty Trunk'

AUDITS=()
for arg in "$@"; do
  case "$arg" in
    --strict) STRICT=1;;
    --keep) KEEP=1;;
    -h|--help) sed -n '2,11p' "$0"; exit 0;;
    -*) echo "fatal: unknown flag $arg" >&2; exit 1;;
    *) AUDITS+=("$arg");;
  esac
done

# no paths given: scan the whole artifact directory, anchored to the repo root so the default
# works from any subdirectory — same posture as the @git* sidecars
if [ ${#AUDITS[@]} -eq 0 ]; then
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "fatal: not a git repository, and no paths given" >&2; exit 1; fi
  cd "$(git rev-parse --show-toplevel)"
  if [ ! -d "$ARTIFACTS" ]; then echo "fatal: no $ARTIFACTS/ to scan" >&2; exit 1; fi
  AUDITS=("$ARTIFACTS"/*.md)
fi

# a directory argument expands to the audit files inside it
EXPANDED=()
for path in "${AUDITS[@]}"; do
  if [ -d "$path" ]; then
    for nested in "$path"/*.md; do [ -f "$nested" ] && EXPANDED+=("$nested"); done
  elif [ -f "$path" ]; then EXPANDED+=("$path")
  else echo "fatal: no such audit file: $path" >&2; exit 1; fi
done
AUDITS=("${EXPANDED[@]}")

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

# emit "START<TAB>END<TAB>HEADING" per `## ` entry, so every check can scope itself to one audit
entries() {
  awk '
    /^## / { if (start) print start "\t" NR - 1 "\t" heading; start = NR; heading = substr($0, 4); next }
    END { if (start) print start "\t" NR "\t" heading }
  ' "$1"
}

# emit "LINENO<TAB>TEXT" for every line inside one entry's `### <name>` block; any heading closes
# it, so a malformed entry cannot bleed its body into the audit that follows
subsection() {
  awk -v s="$2" -v e="$3" -v want="### $4" '
    NR < s || NR > e { next }
    $0 == want { inside = 1; next }
    /^##+ / { inside = 0 }
    inside { print NR "\t" $0 }
  ' "$1"
}

# ==============
# CHECKS
#   each takes an audit path and appends findings; to add one, write a function and list it below
# ==============

# "one audit file per day" — the date in the name is what makes the archive append-only
check_filename() {
  local file=$1 base dir
  base=$(basename "$file")
  dir=$(dirname "$file")
  if ! printf '%s' "$base" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}\.md$'; then
    err "$file" 1 filename "one audit file per day, named YYYY-MM-DD.md"
  fi
  case "$dir" in
    "$ARTIFACTS"|"./$ARTIFACTS"|*"/$ARTIFACTS") ;;
    *) warn "$file" 1 location "audit archives live in $ARTIFACTS/";;
  esac
}

# "tracked in git"
check_tracked() {
  local file=$1
  if ! git ls-files --error-unmatch "$file" >/dev/null 2>&1; then
    warn "$file" 1 untracked "audits are tracked in git; this one is not committed yet"
  fi
}

# the sidecar seeds the file with its own path as the h1, so a mismatch means the file was
# copied from another day — and a copied header is how two days of audits end up in one file
check_header() {
  local file=$1 expected actual
  expected="# $ARTIFACTS/$(basename "$file")"
  actual=$(sed -n '1p' "$file")
  if [ "$actual" != "$expected" ]; then
    err "$file" 1 header "line 1 must read '$expected'"
  fi
}

# "appended each run, many audits per file" — numbering and timestamps are the append order
check_entries() {
  local file=$1 start end heading number stamp expected=1 previous='' count=0 date
  date=$(basename "$file" .md)
  while IFS=$'\t' read -r start end heading; do
    count=$((count + 1))
    if ! printf '%s' "$heading" \
      | grep -qE '^Audit #[0-9]+: [0-9]{4}-[0-9]{2}-[0-9]{2} ([01][0-9]|2[0-3]):[0-5][0-9]$'; then
      err "$file" "$start" entry_heading "entries read '## Audit #N: YYYY-MM-DD HH:MM'"
      continue
    fi
    number=$(printf '%s' "$heading" | sed -n 's/^Audit #\([0-9]\{1,\}\):.*/\1/p')
    stamp=$(printf '%s' "$heading" | sed -n 's/^Audit #[0-9]\{1,\}: \(.*\)$/\1/p')
    if [ "$number" -ne "$expected" ]; then
      err "$file" "$start" entry_numbering "audit $number where $expected was expected"
    fi
    expected=$((number + 1))
    case "$stamp" in
      "$date "*) ;;
      *) err "$file" "$start" entry_date "timestamped $stamp in the file for $date";;
    esac
    if [ -n "$previous" ] && [[ "$stamp" < "$previous" ]]; then
      warn "$file" "$start" entry_order "timestamp precedes the audit above it; each run appends"
    fi
    previous=$stamp
  done < <(entries "$file")
  if [ "$count" -eq 0 ]; then
    warn "$file" 1 empty "seeded, holds no audits yet"
  fi
}

# the four subsections, in the template's order; an audit missing `outcome` is an audit nobody
# ever closed, and reordering them breaks reading two days of audits side by side
check_subsections() {
  local file=$1 start end heading actual
  while IFS=$'\t' read -r start end heading; do
    actual=$(awk -v s="$start" -v e="$end" 'NR >= s && NR <= e && /^### / { print substr($0, 5) }' "$file")
    if [ -z "$actual" ]; then
      err "$file" "$start" section_order "no ### subsections; expected state>findings>resolutions>outcome"
    elif [ "$actual" != "$EXPECTED_SECTIONS" ]; then
      err "$file" "$start" section_order "got $(printf '%s' "$actual" | tr '\n' '>' | sed 's/>$//')"
    fi
  done < <(entries "$file")
}

# "`findings` lead with the label the trigger assigned" as a "numbered list of issues, each with
# its label and the branch/file it names"
check_findings() {
  local file=$1 start end heading lineno text number label expected count
  while IFS=$'\t' read -r start end heading; do
    expected=1
    count=0
    while IFS=$'\t' read -r lineno text; do
      number=$(printf '%s' "$text" | sed -n 's/^\([0-9]\{1,\}\)\. .*/\1/p')
      if [ -z "$number" ]; then continue; fi
      count=$((count + 1))
      if [ "$number" -ne "$expected" ]; then
        err "$file" "$lineno" finding_numbering "finding $number where $expected was expected"
      fi
      expected=$((number + 1))
      if ! printf '%s' "$text" | grep -qE '^[0-9]+\. \*\*[^*]+\*\* — .'; then
        err "$file" "$lineno" finding_shape 'findings read "N. **Label** — what is wrong, and on what"'
        continue
      fi
      label=$(printf '%s' "$text" | sed -n 's/^[0-9]\{1,\}\. \*\*\([^*]*\)\*\*.*/\1/p')
      if ! printf '%s' "$label" | grep -qE "^($KNOWN_LABELS)\$"; then
        warn "$file" "$lineno" finding_label "'$label' is not a label the trigger assigns"
      fi
    done < <(subsection "$file" "$start" "$end" findings)
    if [ "$count" -eq 0 ]; then
      warn "$file" "$start" no_findings "no numbered findings; a clean audit says so in one line"
    fi
  done < <(entries "$file")
}

# "resolution steps per finding, manual command first, `@agent` shortcut second" — per finding,
# so a count mismatch means a finding shipped with nothing the user can do about it
check_resolutions() {
  local file=$1 start end heading lineno text found=0 fixed=0
  while IFS=$'\t' read -r start end heading; do
    found=$(subsection "$file" "$start" "$end" findings | cut -f2- | grep -cE '^[0-9]+\. ' || true)
    fixed=0
    while IFS=$'\t' read -r lineno text; do
      if ! printf '%s' "$text" | grep -qE '^[0-9]+\. '; then continue; fi
      fixed=$((fixed + 1))
      if ! printf '%s' "$text" | grep -qE '`|@git'; then
        warn "$file" "$lineno" resolution_shape "name a command or an @agent shortcut, not prose"
      fi
    done < <(subsection "$file" "$start" "$end" resolutions)
    if [ "$found" -ne "$fixed" ]; then
      err "$file" "$start" resolution_parity "$found finding(s), $fixed resolution(s); one per finding"
    fi
  done < <(entries "$file")
}

# "what the user actually did, appended after the fact; `pending` until then" — blank is neither
check_outcome() {
  local file=$1 start end heading body
  while IFS=$'\t' read -r start end heading; do
    body=$(subsection "$file" "$start" "$end" outcome | cut -f2- | grep -v '^[[:space:]]*$' || true)
    if [ -z "$body" ]; then
      err "$file" "$start" outcome 'outcome reads `pending` until the user acts, never blank'
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

# "skip the raw telemetry dump; keep the read of it, not the printout" — a fenced block in an
# audit is almost always that dump, and an unclosed fence swallows every audit after it
check_fences() {
  local file=$1 hit count=0
  while IFS= read -r hit; do
    if [ -z "$hit" ]; then continue; fi
    count=$((count + 1))
    if [ $((count % 2)) -eq 1 ]; then
      warn "$file" "${hit%%:*}" telemetry_dump "keep the read of the telemetry, not the printout"
    fi
  done < <(grep -nE '^[[:space:]]*```' "$file" || true)
  if [ $((count % 2)) -ne 0 ]; then
    err "$file" 1 fences "$count fence markers; one is unclosed"
  fi
}

# scaffolding left in a shipped artifact reads as fact to everyone downstream
check_placeholders() {
  local file=$1 hit token
  while IFS= read -r hit; do
    if [ -z "$hit" ]; then continue; fi
    token=$(printf '%s' "${hit#*:}" \
      | grep -oE 'YYYY-MM-DD|HH:MM|\*example:\*|repeat the above format' | head -n 1)
    err "$file" "${hit%%:*}" placeholder "template scaffolding survived: $token"
  done < <(grep -nE 'YYYY-MM-DD|HH:MM|\*example:\*|repeat the above format' "$file" || true)
}


# --- run list (add new checks here) ---
for audit in "${AUDITS[@]}"; do
  check_filename    "$audit"
  check_tracked     "$audit"
  check_header      "$audit"
  check_entries     "$audit"
  check_subsections "$audit"
  check_findings    "$audit"
  check_resolutions "$audit"
  check_outcome     "$audit"
  check_width       "$audit"
  check_fences      "$audit"
  check_placeholders "$audit"
  scan_secrets      "$audit"
done

# ==============
# TELEMETRY
# ==============
ERRORS=$(grep -c '^ERROR|' "$FINDINGS" || true)
WARNINGS=$(grep -c '^WARN|' "$FINDINGS" || true)
SECRETS=$(grep -c '|secret|' "$FINDINGS" || true)

cat <<EOF

=== audits.sh sidecar ===
template: $TEMPLATE
scanned: ${#AUDITS[@]} audit file(s)
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
- audits capture repo state at a moment in time, so none of them is ever edited after the fact
- unresolved findings carry forward by restating them in the newest audit, never by editing an old one
- every finding names the branch or file it is about, not just the class of problem
- resolutions run the manual command first and the `@agent` shortcut second
- the outcome is what the user actually did, appended after the fact, not what was recommended
- state reads like a briefing: how and why the repo got into this shape
- err on the side of brevity, not completeness
- a key that reached a commit is already leaked; rotate it before rewriting anything
========================
EOF

if [ "$ERRORS" -gt 0 ]; then exit 1; fi
if [ "$STRICT" -eq 1 ] && [ "$WARNINGS" -gt 0 ]; then exit 1; fi
exit 0

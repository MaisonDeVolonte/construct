#!/bin/bash
# ==========================================================
# @file git.sh - git automation pair validator sidecar
# ==========================================================
# @description
# - sidecar for `git.md` — asserts every `@git*` trigger doc and its shell sidecar hold together
# - one check per machine-checkable rule; every rule needing judgement prints as a human checklist
# - ERROR breaks a rule the template states outright; WARN names a smell the template tolerates
# - defaults to every pair in `AGENTS/git/`; pass a doc, a sidecar, or a directory to scope it
# - `--strict` promotes warnings to errors; exits 1 on any error, 0 otherwise
# @see AGENTS.md, AGENTS/shared/secrets.sh, AGENTS/templates/git.md, AGENTS/git/, AGENTS/templates/plans.sh, .github/workflows/ci.yml

set -euo pipefail

# ==============
# PREFLIGHT
# ==============
# the shared checks sit beside this file, not beside the repo being scanned: resolve them before
# anything cds to a repo root, since BASH_SOURCE arrives relative and would follow that cd
SHARED=$(cd "$(dirname "${BASH_SOURCE[0]}")/../shared" 2>/dev/null && pwd || true)
if [ ! -f "$SHARED/secrets.sh" ]; then
  echo "fatal: no AGENTS/shared/secrets.sh beside this sidecar" >&2; exit 1; fi
# shellcheck source=../shared/secrets.sh
. "$SHARED/secrets.sh"

STRICT=0
TEMPLATE="AGENTS/templates/git.md"
TRIGGERS="AGENTS/git"

# the postures the index assigns; a trigger nobody can tell the blast radius of is a trap
POSTURES='READ-ONLY|SAFE|GATED|DESTRUCTIVE|RELEASE'

PAIRS=()
for arg in "$@"; do
  case "$arg" in
    --strict) STRICT=1;;
    -h|--help) sed -n '2,11p' "$0"; exit 0;;
    -*) echo "fatal: unknown flag $arg" >&2; exit 1;;
    *) PAIRS+=("$arg");;
  esac
done

# every check resolves paths from the repo root, since a trigger doc names its sidecar by full path
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "fatal: not a git repository" >&2; exit 1; fi
cd "$(git rev-parse --show-toplevel)"

if [ ${#PAIRS[@]} -eq 0 ]; then
  if [ ! -d "$TRIGGERS" ]; then echo "fatal: no $TRIGGERS/ to scan" >&2; exit 1; fi
  PAIRS=("$TRIGGERS")
fi

# a pair is named by its doc, so a directory expands to the docs inside it and a sidecar maps back
# to the doc that is supposed to drive it — that mapping is what surfaces an orphaned script
EXPANDED=()
for path in "${PAIRS[@]}"; do
  if [ -d "$path" ]; then
    for nested in "$path"/*.md; do [ -f "$nested" ] && EXPANDED+=("$nested"); done
    for nested in "$path"/*.sh; do
      [ -f "$nested" ] || continue
      [ -f "${nested%.sh}.md" ] || EXPANDED+=("$nested")
    done
  elif [ -f "$path" ]; then EXPANDED+=("$path")
  else echo "fatal: no such trigger file: $path" >&2; exit 1; fi
done
PAIRS=("${EXPANDED[@]}")

# the index that documents each trigger: a host project reaches it through the AGENTS.md symlink,
# and this repo is the one place where the same file is called README.md
INDEX=''
if [ -f AGENTS.md ]; then INDEX=AGENTS.md
elif [ -f README.md ]; then INDEX=README.md; fi

# findings collect as "SEV|file|line|category|detail" — line is its own field so the report can
# sort numerically; joining it to the path first sorts 121 above 31. the run fails on ERROR only
FINDINGS=$(mktemp)
trap 'rm -f "$FINDINGS"' EXIT

err()  { printf 'ERROR|%s|%s|%s|%s\n' "$1" "$2" "$3" "$4" >> "$FINDINGS"; }
warn() { printf 'WARN|%s|%s|%s|%s\n' "$1" "$2" "$3" "$4" >> "$FINDINGS"; }

# the line a pattern first lands on, so a finding points at the file's own line rather than line 1
where() {
  local hit
  hit=$(grep -nE "$2" "$1" 2>/dev/null | head -n 1 | cut -d: -f1 || true)
  printf '%s' "${hit:-1}"
}

# ==============
# CHECKS
#   each takes a doc path and appends findings; to add one, write a function and list it below
# ==============

# "`AGENTS/git/` — one `@git*` trigger doc per workflow, each paired with its shell sidecar"
check_pair() {
  local doc=$1 name sidecar
  name=$(basename "$doc" .md)
  sidecar="$TRIGGERS/$name.sh"
  if ! printf '%s' "$(basename "$doc")" | grep -qE '^git[a-z]+\.md$'; then
    err "$doc" 1 filename "trigger docs are named git<workflow>.md, all lowercase"
  fi
  if [ ! -f "$sidecar" ]; then
    err "$doc" 1 unpaired "no $sidecar; every trigger doc starts with a shell sidecar"
    return 0
  fi
  if [ ! -x "$sidecar" ]; then
    warn "$sidecar" 1 not_executable "chmod +x, so the documented invocation works as written"
  fi
}

# the wayfinding block from AGENTS.md, which is how anyone reading the doc learns its boundaries
check_doc_wayfinding() {
  local doc=$1 name
  name=$(basename "$doc" .md)
  if [ "$(sed -n '1p' "$doc")" != '```javascript' ]; then
    err "$doc" 1 wayfinding "line 1 opens the wayfinding block: \`\`\`javascript"
  fi
  if ! grep -qE "^ \* @file $name\.md - " "$doc"; then
    err "$doc" 1 wayfinding "@file must read '$name.md - <short, specific title>'"
  fi
  if ! grep -q '^ \* @description' "$doc"; then
    err "$doc" 1 wayfinding "no @description; the header is what stops a reader guessing"
  fi
  if ! grep -q '^ \* @see' "$doc"; then
    err "$doc" 1 wayfinding "no @see; list every related internal file"
    return 0
  fi
  if ! grep -q "^ \* @see.*$TEMPLATE" "$doc"; then
    warn "$doc" "$(where "$doc" '^ \* @see')" wayfinding "@see should name $TEMPLATE, the shape it follows"
  fi
  if ! grep -q "^ \* @see.*$TRIGGERS/$name\.sh" "$doc"; then
    warn "$doc" "$(where "$doc" '^ \* @see')" wayfinding "@see should name its own sidecar, $TRIGGERS/$name.sh"
  fi
}

# "ran only on explicit `@gitautomation` commands" — the whole safety model rests on this line
check_trigger() {
  local doc=$1 name
  name=$(basename "$doc" .md)
  if ! grep -qE "^\*\*@$name:\*\*.*(ONLY|only) on explicit" "$doc"; then
    err "$doc" 1 trigger "state it outright: '**@$name:** Run ONLY on explicit \`@$name\` command'"
  fi
}

# "starts with a native shell script sidecar" — the doc has to actually run the thing, in a block
# somebody can copy, and the path has to be the sidecar that belongs to it
check_invocation() {
  local doc=$1 name
  name=$(basename "$doc" .md)
  if ! grep -qE "^[[:space:]]*$TRIGGERS/$name\.sh([[:space:]]|$)" "$doc"; then
    err "$doc" 1 invocation "the doc never runs $TRIGGERS/$name.sh"
  fi
  if ! grep -qE '^[[:space:]]*```bash' "$doc"; then
    warn "$doc" 1 invocation "put the command in a \`\`\`bash block, exactly as it should be run"
  fi
}

# "fail: outputs raw terminal errors" and "success: evaluates telemetry and executes subsequent
# actions" — both branches, however each doc words them, since a sidecar that reports a conflict
# separately reads `> 1` where a two-state one reads `> 0`
check_branches() {
  local doc=$1
  # a report-only sidecar has exactly one path by contract, so it has no failure branch to document
  if grep -qE 'report-only|never fails' "$doc"; then return 0; fi
  if ! grep -qE 'exit code[[:space:]]+(>|>=|!=)[[:space:]]*[0-9]|nonzero' "$doc"; then
    err "$doc" 1 no_failure_branch "no failure branch; say what happens when the sidecar exits nonzero"
  fi
  if ! grep -qE 'exit code[[:space:]]+=+[[:space:]]*0' "$doc"; then
    err "$doc" 1 no_success_branch "no success branch; say what the telemetry means and what follows"
  fi
}

# a trigger that writes a dated artifact has to name the template that artifact must match, or the
# agent writing it has nothing to follow
check_artifact() {
  local doc=$1 type
  for type in audits brutal insights logs plans study; do
    if ! grep -q "docs/$type/" "$doc"; then continue; fi
    if ! grep -q "AGENTS/templates/$type\.md" "$doc"; then
      warn "$doc" "$(where "$doc" "docs/$type/")" artifact \
        "writes docs/$type/ without naming AGENTS/templates/$type.md"
    fi
  done
}

# the sidecar is the half that touches git, so its own header and its shebang are load-bearing
check_sidecar_header() {
  local doc=$1 name sidecar
  name=$(basename "$doc" .md)
  sidecar="$TRIGGERS/$name.sh"
  if [ ! -f "$sidecar" ]; then return 0; fi
  if [ "$(sed -n '1p' "$sidecar")" != '#!/bin/bash' ]; then
    err "$sidecar" 1 shebang "line 1 must read '#!/bin/bash'"
  fi
  if ! grep -qE "^# @file $name\.sh - " "$sidecar"; then
    err "$sidecar" 1 wayfinding "@file must read '$name.sh - <short, specific title>'"
  fi
  if ! grep -q '^# @description' "$sidecar"; then
    err "$sidecar" 1 wayfinding "no @description; the header is what stops a reader guessing"
  fi
  if ! grep -q '^# @see' "$sidecar"; then
    err "$sidecar" 1 wayfinding "no @see; list every related internal file"
  fi
  # a read-only diagnostic may want to survive a failing probe, so this one only ever warns
  if ! grep -q 'set -euo pipefail' "$sidecar"; then
    warn "$sidecar" 1 no_strict_mode "no 'set -euo pipefail'; a silent partial run is worse than a stop"
  fi
}

# "the required check that lets `gh pr merge --auto` engage" runs the same two gates, so a sidecar
# that fails them locally has already failed ci
check_sidecar_lint() {
  local doc=$1 name sidecar hit line
  name=$(basename "$doc" .md)
  sidecar="$TRIGGERS/$name.sh"
  if [ ! -f "$sidecar" ]; then return 0; fi
  if ! bash -n "$sidecar" 2>/dev/null; then
    err "$sidecar" 1 syntax "does not parse; 'bash -n' is the first gate ci runs"
    return 0
  fi
  if ! command -v shellcheck >/dev/null 2>&1; then return 0; fi
  while IFS= read -r hit; do
    if [ -z "$hit" ]; then continue; fi
    line=$(printf '%s' "$hit" | cut -d: -f2)
    warn "$sidecar" "${line:-1}" shellcheck "$(printf '%s' "$hit" | cut -d: -f4- | sed 's/^ *//')"
  done < <(shellcheck -f gcc --severity=warning "$sidecar" 2>/dev/null || true)
}

# a trigger the index never lists is a trigger nobody discovers, and one listed without its posture
# is one nobody can judge the blast radius of before running it
check_index() {
  local doc=$1 name entry
  name=$(basename "$doc" .md)
  if [ -z "$INDEX" ]; then return 0; fi
  entry=$(grep -nE "\(AGENTS/git/$name\.md\)" "$INDEX" | head -n 1 || true)
  if [ -z "$entry" ]; then
    err "$doc" 1 unindexed "$INDEX does not list @$name; nobody will find it"
    return 0
  fi
  if ! printf '%s' "$entry" | grep -qE "($POSTURES)"; then
    warn "$INDEX" "${entry%%:*}" no_posture "@$name is listed without a posture keyword"
  fi
}

# both halves of a pair get scanned, since a sidecar is as likely to hold a pasted token as its doc
check_scrub() {
  local doc=$1 name file
  name=$(basename "$doc" .md)
  for file in "$doc" "$TRIGGERS/$name.sh"; do
    if [ -f "$file" ]; then scan_secrets "$file"; fi
  done
}

# --- run list (add new checks here) ---
for pair in "${PAIRS[@]}"; do
  # a sidecar reaching this loop has no doc at all, so the pair checks have nothing to read
  case "$pair" in
    *.sh)
      err "$pair" 1 unpaired "no ${pair%.sh}.md; a sidecar without a trigger doc is unreachable"
      continue;;
  esac
  check_pair            "$pair"
  check_doc_wayfinding  "$pair"
  check_trigger         "$pair"
  check_invocation      "$pair"
  check_branches        "$pair"
  check_artifact        "$pair"
  check_sidecar_header  "$pair"
  check_sidecar_lint    "$pair"
  check_index           "$pair"
  check_scrub           "$pair"
done

# ==============
# TELEMETRY
# ==============
ERRORS=$(grep -c '^ERROR|' "$FINDINGS" || true)
WARNINGS=$(grep -c '^WARN|' "$FINDINGS" || true)
SECRETS=$(grep -c '|secret|' "$FINDINGS" || true)

cat <<EOF

=== git.sh sidecar ===
template: $TEMPLATE
scanned: ${#PAIRS[@]} pair(s)
index: ${INDEX:-none found}
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
- the trigger fires only on the explicit command, and is never inferred from intent
- failure hands back the raw terminal error, never a summary or a paraphrase of it
- success evaluates the telemetry first, and only then takes the documented action
- every scenario the sidecar can report has a branch in the doc that reads it
- destructive steps stay gated behind an explicit confirmation the user has to type
- the sidecar is the only half that touches git; the doc only decides what its output means
- the posture in the index matches what the sidecar actually does, not what it was written to do
- a key that reached a commit is already leaked; rotate it before rewriting anything
========================
EOF

if [ "$ERRORS" -gt 0 ]; then exit 1; fi
if [ "$STRICT" -eq 1 ] && [ "$WARNINGS" -gt 0 ]; then exit 1; fi
exit 0

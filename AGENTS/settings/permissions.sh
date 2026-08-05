#!/bin/bash
# =========================================================
# @file permissions.sh - permissions audit for this project
# =========================================================
# @description
# - replays `corpus.tsv` against the real hook, then audits the settings file structurally
# - NEVER executes a corpus line; every one is passed to the hook as a string and nothing more
# - tier 1 is ground truth, since the hook it feeds is the artifact under test
# - tier 2 is structural fact: drift, dead rules, and which allow rule covers an unnamed command
# - it deliberately does NOT model the permission matcher, so it never reports a rule as covering
# - `--strict` promotes warnings to errors, `--keep` preserves scratch; exits 1 on any error
# @see AGENTS.md, AGENTS/settings/corpus.tsv, AGENTS/hooks/pretooluse.sh, .claude/settings.json

set -euo pipefail

# ==============
# PREFLIGHT
# ==============
# the corpus and the hook sit beside this file, not beside the repo being scanned: resolve them
# before anything cds to a repo root, since BASH_SOURCE arrives relative and would follow that cd
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)
CORPUS="$HERE/corpus.tsv"
HOOK="$HERE/../hooks/pretooluse.sh"
if [ ! -f "$CORPUS" ]; then echo "fatal: no corpus.tsv beside this script" >&2; exit 1; fi
if [ ! -f "$HOOK" ]; then echo "fatal: no ../hooks/pretooluse.sh beside this script" >&2; exit 1; fi

STRICT=0
KEEP=0
for arg in "$@"; do
  case "$arg" in
    --strict) STRICT=1;;
    --keep) KEEP=1;;
    -h|--help) sed -n '2,13p' "$0"; exit 0;;
    *) echo "fatal: unknown flag $arg" >&2; exit 1;;
  esac
done

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "fatal: not a git repository" >&2; exit 1; fi
cd "$(git rev-parse --show-toplevel)"

# a project's rules can be split across three files, and the audit is meaningless if it reads one
SETTINGS=()
for candidate in .claude/settings.json .claude/settings.local.json "$HOME/.claude/settings.json"; do
  if [ -f "$candidate" ]; then SETTINGS+=("$candidate"); fi
done

# repo-local scratch: the sandbox denies writes outside cwd, and macos mktemp ignores TMPDIR
TMPROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)/tmp"
TMPTAG=$(basename "${BASH_SOURCE[0]}" .sh)
mkdir -p "$TMPROOT"
FINDINGS=$(mktemp "$TMPROOT/$TMPTAG-findings.XXXXXX")
SCRATCH=$(mktemp -d "$TMPROOT/$TMPTAG-scratch.XXXXXX")
# a failed run leaves scratch behind to read; --keep does the same after a clean one
cleanup() { st=$?; if [ "$KEEP" -eq 0 ] && [ "$st" -eq 0 ]; then rm -rf "$FINDINGS" "$SCRATCH"; fi; }
trap cleanup EXIT

err()  { printf 'ERROR|%s|%s|%s\n' "$1" "$2" "$3" >> "$FINDINGS"; }
warn() { printf 'WARN|%s|%s|%s\n' "$1" "$2" "$3" >> "$FINDINGS"; }

# every deny and allow rule across every settings file that exists, one per line
rules_of() {
  local which=$1 file
  for file in "${SETTINGS[@]}"; do
    jq -r --arg w "$which" '.permissions[$w][]? // empty' "$file" 2>/dev/null || true
  done
}
rules_of deny  > "$SCRATCH/deny"
rules_of allow > "$SCRATCH/allow"
rules_of ask   > "$SCRATCH/ask"

# the hook answers in json or says nothing at all, and silence is the allow case
hook_verdict() {
  local cmd=$1 out
  out=$(jq -n --arg c "$cmd" '{tool_input:{command:$c}}' | bash "$HOOK" 2>/dev/null || true)
  if [ -z "$out" ]; then printf 'silent'; else printf 'deny'; fi
}

# two tokens for a tool that takes a subcommand, one token for everything else
base_of() {
  local cmd=$1 first second
  first=$(printf '%s' "$cmd" | awk '{print $1}')
  second=$(printf '%s' "$cmd" | awk '{print $2}')
  case "$first" in
    git|gh|npm|yarn|pnpm|bun|docker|kubectl|aws|terraform|prisma)
      case "$second" in
        -*|"") printf '%s' "$first";;
        *) printf '%s %s' "$first" "$second";;
      esac;;
    *) printf '%s' "$first";;
  esac
}

# ==============
# TIER 1 — ground truth
#   the corpus is replayed into the real hook, so these results are exact rather than modelled
# ==============
T1_PASS=0; T1_FAIL=0
tier1() {
  local effect gate cmd verdict
  while IFS=$'\t' read -r effect gate cmd; do
    case "$effect" in ''|'#'*) continue;; esac
    if [ -z "${cmd:-}" ]; then continue; fi
    case "$gate" in hook|none) ;; *) continue;; esac
    verdict=$(hook_verdict "$cmd")
    if [ "$gate" = "hook" ]; then
      if [ "$verdict" = "deny" ]; then T1_PASS=$((T1_PASS + 1))
      else T1_FAIL=$((T1_FAIL + 1)); err "$effect" "$cmd" "the hook lets this through; it is meant to block it"; fi
    else
      if [ "$verdict" = "silent" ]; then T1_PASS=$((T1_PASS + 1))
      else T1_FAIL=$((T1_FAIL + 1)); err "$effect" "$cmd" "the hook blocks legitimate work; over-blocking"; fi
    fi
  done < "$CORPUS"
}

# ==============
# TIER 2 — structural fact
#   nothing here predicts the matcher; each check reports what the files literally say
# ==============

# true when a path in the command is denied for the file tools while bash is left free to reach it
tool_scoped() {
  local cmd=$1 token stem head
  read -r -a PARTS <<< "$cmd"
  for token in "${PARTS[@]}"; do
    # every path shape worth checking carries a slash, so one pattern covers ~/x, ./x and /x
    case "$token" in
      */*) ;;
      *) continue;;
    esac
    stem=$(printf '%s' "$token" | sed -E 's#^~/##; s#^\./##; s#^/##')
    head=${stem%%/*}
    if [ -z "$head" ]; then continue; fi
    if grep -E '^(Read|Edit|Write)\(' "$SCRATCH/deny" | grep -qF -- "$head"; then return 0; fi
  done
  return 1
}

# a command no deny rule names, sitting under an allow wildcard, is auto-approved with no prompt
check_named() {
  local effect gate cmd base T2=0
  while IFS=$'\t' read -r effect gate cmd; do
    case "$effect" in ''|'#'*) continue;; esac
    if [ "$gate" != "deny" ]; then continue; fi
    base=$(base_of "$cmd")
    if grep -qF -- "$base" "$SCRATCH/deny"; then continue; fi
    # the path may be denied for Read, Edit and Write while bash still reaches it: the `cp` gap
    if tool_scoped "$cmd"; then
      err "$effect" "$cmd" "path denied for Read/Edit/Write only; bash reaches it via '$base'"
      T2=$((T2 + 1))
      continue
    fi
    # no deny rule names it, so the only question left is whether something allows it outright
    if grep -qE "^Bash\($(printf '%s' "$base" | awk '{print $1}') \*\)$" "$SCRATCH/allow"; then
      err "$effect" "$cmd" "no deny rule names '$base', and an allow wildcard covers it: auto-approved"
    else
      warn "$effect" "$cmd" "no deny rule names '$base'; it will prompt rather than be refused"
    fi
    T2=$((T2 + 1))
  done < "$CORPUS"
  return 0
}

# the hook keeps its own copy of the protected paths, and nothing keeps the two lists in step
check_drift() {
  local path
  grep -E '^PROTECTED=' "$HOOK" \
    | sed -E "s/^PROTECTED=[\"']?//; s/[\"']$//; s/\\\$PROTECTED//" \
    | tr '|' '\n' \
    | sed -E 's/\\//g; s/[()^$]//g; s/\[.*\]//g; s#/$##' \
    | grep -E '^[a-zA-Z.]' | sort -u > "$SCRATCH/hookpaths"
  # ask counts as a guard here, exactly as it does in settingsaudit.sh: a tracked path cannot be
  # denied, since the deny reaches the macos sandbox and blocks git's own unlink mid-checkout
  cat "$SCRATCH/deny" "$SCRATCH/ask" 2>/dev/null \
    | grep -E '^(Edit|Write)\(' \
    | sed -E 's/^(Edit|Write)\(//; s/\)$//' \
    | sed -E 's#^\*\*/##; s#/\*\*$##; s#\*##g' | sort -u > "$SCRATCH/guardedpaths"
  while IFS= read -r path; do
    if [ -z "$path" ]; then continue; fi
    # containment runs both ways: a broad `AGENTS/**` rule guards `AGENTS/settings` without
    # naming it, so a plain substring search in one direction reports a guard that exists
    if grep -qF -- "$path" "$SCRATCH/guardedpaths"; then continue; fi
    if awk -v p="$path" 'NF && index(p, $0) { hit = 1 } END { exit !hit }' "$SCRATCH/guardedpaths"; then continue; fi
    warn drift "$path" "the hook guards this path, but no Edit/Write deny or ask rule names it"
  done < "$SCRATCH/hookpaths"
  while IFS= read -r path; do
    if [ -z "$path" ]; then continue; fi
    case "$path" in .env*) path=".env";; esac
    if grep -qF -- "$path" "$SCRATCH/hookpaths"; then continue; fi
    # a settings glob and a hook regex spell one path differently, so compare by containment too
    if awk -v p="$path" 'NF && index(p, $0) { hit = 1 } END { exit !hit }' "$SCRATCH/hookpaths"; then continue; fi
    warn drift "$path" "a deny or ask rule guards this path, but the hook would not stop bash writing it"
  done < "$SCRATCH/guardedpaths"
}

# a rule whose prefix is already covered by another in the same list never matches anything
check_dead() {
  local list name a b stem
  for list in deny allow; do
    while IFS= read -r a; do
      if [ -z "$a" ]; then continue; fi
      stem=${a%\*}
      if [ "$stem" = "$a" ]; then continue; fi
      while IFS= read -r b; do
        if [ -z "$b" ] || [ "$a" = "$b" ]; then continue; fi
        case "$b" in
          "$stem"*) warn dead_rule "$b" "already covered by '$a' in the $list list";;
        esac
      done < "$SCRATCH/$list"
    done < "$SCRATCH/$list"
    name=$list
  done
  printf '%s' "$name" >/dev/null
}

# a settings file that does not parse is a settings file the harness silently ignores
check_parse() {
  local file
  for file in "${SETTINGS[@]}"; do
    if ! jq empty "$file" >/dev/null 2>&1; then
      err parse "$file" "does not parse as json; the harness cannot read these rules"
    fi
  done
}

tier1
check_named
check_drift
check_dead
check_parse

# ==============
# TELEMETRY
# ==============
ERRORS=$(grep -c '^ERROR|' "$FINDINGS" || true)
WARNINGS=$(grep -c '^WARN|' "$FINDINGS" || true)
CASES=$(grep -cvE '^#|^$' "$CORPUS" || true)

cat <<EOF

=== permissions.sh audit ===
corpus: $CORPUS
settings: ${SETTINGS[*]:-none found}
hook: $HOOK
cases: $CASES
tier1 replayed: $((T1_PASS + T1_FAIL)) — $T1_PASS held, $T1_FAIL failed
errors: $ERRORS
warnings: $WARNINGS
--- findings ---
EOF

if [ "$ERRORS" -eq 0 ] && [ "$WARNINGS" -eq 0 ]; then
  echo "none — every replayed case held, and the settings files agree with the hook"
else
  sort -t'|' -k1,1 -k2,2 "$FINDINGS" \
    | awk -F'|' '{ printf "%-5s %-22s %-46s %s\n", $1, $2, substr($3, 1, 44), $4 }'
fi

cat <<'EOF'
--- what this audit cannot tell you ---
- it never models the permission matcher, so "no deny rule names it" is not "it is allowed"
- a rule may still fail to match for a reason only the harness knows; test the ones that matter
- neither layer sees inside AGENTS/git/*.sh, so an allow-listed script bypasses both by design
- the hook matches command strings, not intent, so it over-blocks a string that merely names a path
- settings load at session start, so an edited file changes nothing until the session restarts
- a corpus is only as good as its spellings; add one every time a new bypass turns up
============================
EOF

if [ "$ERRORS" -gt 0 ]; then exit 1; fi
if [ "$STRICT" -eq 1 ] && [ "$WARNINGS" -gt 0 ]; then exit 1; fi
exit 0

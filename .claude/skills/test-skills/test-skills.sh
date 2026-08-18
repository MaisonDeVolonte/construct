#!/bin/bash
# =========================================================
# @file test-skills.sh - smoke harness across every sidecar
# =========================================================
# @description
# PAIR
# - sidecar for `test-skills` — proves every skill still executes, and shows the proof per skill
# - `validate-skills` reads a pair, `/operator:scripts` reads what a script reaches; this one RUNS
# - a green row here means the file loaded and its dependencies resolved, never that the skill works
# - the deep run belongs to the trigger a user invokes, which is why no tier below does the work
# TIERS
# - t0 parses: `bash -n`, the shebang, the exec bit, and shellcheck when it is installed
# - t1 answers: `--help` prints its marker and exits 0, and an unknown flag is refused
# - t2 resolves: the sidecar's own `# shellcheck source=`, `@see` and `command -v` lines, statically
# - t3 loads: `--test` prints `test: ok` and exits 0, which proves the guards above it returned
# - a tier only runs when the one before it passed, so one failure reports once rather than four
# - t2 is a static read, so a broken reference is named without the sidecar running at all
# RUN
# - defaults to every pair under `plugins/*/skills/` and `.claude/skills/`; pass a path to scope it
# - `--strict` promotes warnings to errors; exits 1 on any error either way
# - every invocation is capped by `perl -e alarm`, since macos ships no `timeout`
# - a sidecar with no `--test` case is a WARN, so the contract can land skill by skill
# ARTIFACT
# - `.construct/maintainer/test-skills/YYYY-MM-DD.md`, one file per day, appended by the agent
# - reported, never created: this names the path and the count, and the doc says what to write
# @see .claude/skills/test-skills/SKILL.md, plugins/gitgud/shared/handover.sh, .claude/skills/validate-skills/validate-skills.sh, .construct/maintainer/test-skills/

set -euo pipefail

# the doc is read only after this has already run, so help is refused here or not at all; the doc's
# own '## Help' section owns the output, which is why this prints a marker rather than a usage text
case " $* " in *" --help "*|*" -h "*) echo "help: requested"; exit 0;; esac

# the harness answers the contract it enforces, or it would grade every sidecar by a rule its own
# file breaks; it also stops a whole-tree run recursing when this directory comes up in discovery
case " $* " in *" --test "*) echo "test: ok"; exit 0;; esac

# the day's artifact is named here and written by the agent, the same split every other skill in
# this repo makes; nothing under it is written by this run
ARTIFACTS=".construct/maintainer/test-skills"

# ==============
# PREFLIGHT
# ==============
# the block emitters sit beside this file's plugin, not beside the repo under test: resolve them
# before any cd, since BASH_SOURCE arrives relative and would follow that cd somewhere else
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)
SHARED=$(cd "$HERE/../../../plugins/gitgud/shared" 2>/dev/null && pwd || true)
if [ ! -f "$SHARED/handover.sh" ]; then
  echo "fatal: no plugins/gitgud/shared/handover.sh reachable from this sidecar" >&2; exit 1; fi
# shellcheck source=../../../plugins/gitgud/shared/handover.sh
. "$SHARED/handover.sh"

if ! command -v perl >/dev/null 2>&1; then echo "fatal: perl is required and not installed" >&2; exit 1; fi

STRICT=0
TARGETS=()
while [ $# -gt 0 ]; do
  case "$1" in
    # a bare invocation passes one empty string, and keeping it would make TARGETS non-empty and
    # defeat the whole-tree default below, so the run would grade a path named ""
    "") ;;
    --strict) STRICT=1;;
    -*) echo "fatal: unknown flag $1" >&2; exit 1;;
    *) TARGETS+=("$1");;
  esac
  shift
done

require_repo
ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"

# ==============
# SETUP
# ==============
# the cap is per invocation, and only a hung sidecar ever reaches it; help and test both return
# immediately by contract, so a timeout is itself a finding rather than a slow machine
CAP=20

ERRORS=0
WARNINGS=0
SCANNED=0
ROWS=""

# perl's alarm is the portable cap here, since macos ships no timeout(1); the exec keeps the
# sidecar's own exit code intact, and a killed run surfaces as 142 rather than a silent pass
run_capped() {
  perl -e 'alarm shift; exec @ARGV or exit 127' "$CAP" "$@" 2>&1
}

fail() {
  ROWS="${ROWS}$1|$2|FAIL|$3
"
  ERRORS=$((ERRORS + 1))
}

warn() {
  ROWS="${ROWS}$1|$2|WARN|$3
"
  WARNINGS=$((WARNINGS + 1))
}

pass() {
  ROWS="${ROWS}$1|$2|ok|$3
"
}

# ==============
# DISCOVERY
# ==============
# a pair is one directory holding `<name>.sh`, so the sidecar is derived from the folder rather
# than globbed; a directory with two scripts is validate-skills' finding, never this one's
discover() {
  local scope=$1
  find "$scope" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort
}

DIRS=()
if [ ${#TARGETS[@]} -eq 0 ]; then
  for plugin in plugins/*/; do
    [ -d "$plugin/skills" ] || continue
    while IFS= read -r d; do [ -n "$d" ] && DIRS+=("$d"); done <<EOF
$(discover "$plugin/skills")
EOF
  done
  while IFS= read -r d; do [ -n "$d" ] && DIRS+=("$d"); done <<EOF
$(discover ".claude/skills")
EOF
else
  for t in "${TARGETS[@]}"; do
    t=${t%/}
    if [ -f "$t" ]; then DIRS+=("$(dirname "$t")")
    elif [ -d "$t" ]; then DIRS+=("$t")
    else echo "fatal: no such path $t" >&2; exit 1; fi
  done
fi

if [ ${#DIRS[@]} -eq 0 ]; then echo "fatal: no skill directories found" >&2; exit 1; fi

# ==============
# TIERS
# ==============
for dir in "${DIRS[@]}"; do
  name=$(basename "$dir")
  sidecar="$dir/$name.sh"

  # a doc with no sidecar runs nothing, so it has nothing to smoke test; validate-skills owns
  # whether that pairing is legal, and reporting it twice would put one break in two tools
  if [ ! -f "$sidecar" ]; then continue; fi
  SCANNED=$((SCANNED + 1))

  # the invocation is what a block header and a `/` menu entry both print, so it is derived the
  # one way: a plugin skill is `plugin:skill`, and a maintainer skill is its bare name
  case "$dir" in
    plugins/*) invocation="$(echo "$dir" | cut -d/ -f2):$name";;
    *) invocation="$name";;
  esac

  # ---- t0: it parses ----
  if ! out=$(bash -n "$sidecar" 2>&1); then
    fail "$invocation" "t0-parse" "$(printf '%s' "$out" | head -1)"
    continue
  fi
  if [ "$(head -1 "$sidecar")" != "#!/bin/bash" ]; then
    warn "$invocation" "t0-shebang" "line 1 is not #!/bin/bash"
  fi
  if command -v shellcheck >/dev/null 2>&1; then
    if ! out=$(shellcheck -S error "$sidecar" 2>&1); then
      fail "$invocation" "t0-shellcheck" "$(printf '%s' "$out" | grep -c '^In ' | tr -d ' ') error(s)"
      continue
    fi
  fi

  # the exec bit is what an install copies, and a sidecar without it dies on someone else's
  # machine with a permission error from a path they never wrote
  mode=$(git ls-files -s "$sidecar" 2>/dev/null | awk '{print $1}')
  if [ -n "$mode" ] && [ "$mode" != "100755" ]; then
    fail "$invocation" "t0-mode" "$mode, repair: git update-index --chmod=+x $sidecar"
  fi

  # ---- t1: it answers ----
  out=$(run_capped bash "$sidecar" --help || true)
  case "$out" in
    *"help: requested"*) ;;
    *) fail "$invocation" "t1-help" "no 'help: requested' marker"; continue;;
  esac

  # the doc's argument-hint declares what a skill takes, so the flag question is asked only of one
  # that declares NOTHING past its flags; a skill taking prose or a path reads the word as its own
  hint=$(sed -n 's/^argument-hint: *"\(.*\)"/\1/p' "$dir/SKILL.md" 2>/dev/null | head -1)
  rest=$(printf '%s' "$hint" | sed -E 's/\[--[a-z-]+\]//g; s/--[a-z-]+//g; s/[^[:alnum:]]//g')
  if [ -z "$rest" ]; then
    set +e
    out=$(run_capped bash "$sidecar" --zzz-not-a-flag)
    code=$?
    set -e
    # refusal is a non-zero exit whatever wording it carries, since `fatal:` and `usage:` both
    # refuse; a confirm gate refuses too, and prices the run before it ever parses a flag
    case "$out" in
      *"confirm: required"*) ;;
      *) [ "$code" -ne 0 ] || warn "$invocation" "t1-flag" "takes no argument, ran on one anyway";;
    esac
  fi

  # ---- t2: its references resolve ----
  # every check here reads the sidecar's own text, so a broken reference is named whether or not
  # the file would run; the sidecar's directory anchors a source= line, the repo root anchors @see
  here=$(cd "$dir" && pwd)
  checks=0; notes=0; broken=""

  # a `# shellcheck source=<relative>` line names a file this sidecar sources at run time, and the
  # sourced file going missing is the break that takes a whole plugin down, so it is checked first
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    checks=$((checks + 1))
    [ -f "$here/$rel" ] || broken="$broken source:$rel"
  done <<EOF
$(sed -n 's/^# shellcheck source=\([^ ]*\).*/\1/p' "$sidecar")
EOF

  # the wayfinder names every path this pair depends on, and a rename that missed one is exactly
  # the break this tool exists to catch; a trailing slash is an artifact dir, unwritten until a run
  while IFS= read -r ref; do
    [ -n "$ref" ] || continue
    checks=$((checks + 1))
    case "$ref" in
      */) [ -d "$ref" ] || notes=$((notes + 1));;
      *)  [ -e "$ref" ] || broken="$broken see:$ref";;
    esac
  done <<EOF
$(sed -n 's/^# @see //p' "$sidecar" | tr ',' '\n' | sed 's/^ *//;s/ *$//')
EOF

  # a sidecar guarding on `command -v jq` dies at its own preflight when jq is absent, and the
  # message names a machine problem rather than a repo one; name it here before the run does
  while IFS= read -r tool; do
    [ -n "$tool" ] || continue
    checks=$((checks + 1))
    command -v "$tool" >/dev/null 2>&1 || broken="$broken tool:$tool"
  done <<EOF
$(sed -n 's/.*command -v \([a-zA-Z0-9_-]*\).*/\1/p' "$sidecar" | sort -u)
EOF

  if [ -n "$broken" ]; then
    fail "$invocation" "t2-refs" "unresolved:$broken"
    continue
  fi

  # ---- t3: it loads ----
  # the marker is the whole contract: the case sits above the body, so printing it proves the
  # guards before it returned rather than exiting on a real refusal
  if ! grep -q 'echo "test: ok"' "$sidecar"; then
    warn "$invocation" "t3-case" "no --test case; contract not adopted"
    continue
  fi

  set +e
  out=$(run_capped bash "$sidecar" --test)
  code=$?
  set -e

  if [ "$code" -eq 142 ] || [ "$code" -eq 14 ]; then
    fail "$invocation" "t3-test" "timed out at ${CAP}s"
    continue
  fi
  case "$out" in
    *"test: ok"*) ;;
    *) fail "$invocation" "t3-test" "exit $code, no 'test: ok' marker"; continue;;
  esac

  pass "$invocation" "t3-test" "${checks} reference(s) resolved, ${notes} unwritten"
done

# ==============
# TELEMETRY
# ==============
# one file per day: the count is read off the headings already in it, so the number the agent
# writes survives a run that reported nothing. `grep -c` exits 1 on no match, hence the `|| true`
TODAYS_AUDIT="$ARTIFACTS/$(date +%Y-%m-%d).md"
if [ -f "$TODAYS_AUDIT" ];
then AUDIT_COUNT=$(grep -c '^## Smoke Audit #' "$TODAYS_AUDIT" || true)
else AUDIT_COUNT=0; fi
AUDIT_COUNT=${AUDIT_COUNT:-0}

telemetry_open "test-skills"
telemetry_line "scanned" "$SCANNED sidecar(s)"
telemetry_line "adopted" "$(printf '%s' "$ROWS" | grep -c 't3-case' | tr -d ' ') without a --test case"
telemetry_line "errors" "$ERRORS"
telemetry_line "warnings" "$WARNINGS"
telemetry_line "audit_file" "$TODAYS_AUDIT"
telemetry_line "audit_count" "$AUDIT_COUNT"
telemetry_line "next_audit" "$((AUDIT_COUNT + 1))"
telemetry_line "timestamp" "$(date '+%Y-%m-%d %H:%M')"

echo
echo "| skill | tier | result | detail |"
echo "|---|---|---|---|"
printf '%s' "$ROWS" | awk -F'|' 'NF{printf "| %s | %s | %s | %s |\n", $1, $2, $3, $4}'

handover_open "test-skills"
if [ "$ERRORS" -gt 0 ] || { [ "$STRICT" -eq 1 ] && [ "$WARNINGS" -gt 0 ]; }; then
  echo "# rerun one skill alone to read its findings in full"
  printf '%s' "$ROWS" | awk -F'|' '$3=="FAIL"{print "bash .claude/skills/test-skills/test-skills.sh " $1}' \
    | head -3 | sed 's/test-skills.sh \(.*\):\(.*\)/test-skills.sh plugins\/\1\/skills\/\2/'
else
  echo "# nothing to run: every sidecar parsed, answered, resolved its references and loaded"
fi
echo "====================="

if [ "$ERRORS" -gt 0 ]; then exit 1; fi
if [ "$STRICT" -eq 1 ] && [ "$WARNINGS" -gt 0 ]; then exit 1; fi
exit 0

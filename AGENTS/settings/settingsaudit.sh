#!/bin/bash
# ==========================================================
# @file settingsaudit.sh - settings stack auditor and prober
# ==========================================================
# @description
# - sidecar for `@settingsaudit` — audits the settings stack, then probes it live
# - read-only by contract: it reports and repairs nothing, since every fix is the user's to make
# - STATIC checks read the files: parse, drift, verb symmetry, scope placement, hygiene
# - LIVE probes exercise the boundary, because a config can be perfect while the gate is dead
# - a latent fault is the failure this exists for: protection that stopped working in silence
# - wraps permissions.sh and scopes.sh rather than replacing them, surfacing their error counts
# - a tracked path reads as guarded at `ask`, since `deny` reaches the sandbox and blocks git itself
# - `--static` skips the probes, `--quick` skips the wrapped sidecars, `--strict` fails on warnings
# @see AGENTS.md, AGENTS/templates/audits.md, AGENTS/templates/git.md,
#      AGENTS/settings/permissions.sh, AGENTS/settings/scopes.sh, docs/audits/

set -euo pipefail

# ==============
# PREFLIGHT
# ==============
# the shared scan sits beside this file, not beside the repo being audited: resolve it before any
# cd, since BASH_SOURCE arrives relative and would follow that cd to somewhere it does not exist
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)
if [ ! -f "$HERE/secrets.sh" ]; then
  echo "fatal: no AGENTS/settings/secrets.sh beside this sidecar" >&2; exit 1; fi
# shellcheck source=./secrets.sh
. "$HERE/secrets.sh"

if ! command -v jq >/dev/null 2>&1; then echo "fatal: jq is required" >&2; exit 1; fi
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "fatal: not a git repository" >&2; exit 1; fi

STATIC_ONLY=0
QUICK=0
STRICT=0
while [ $# -gt 0 ]; do
  case "$1" in
    --static) STATIC_ONLY=1;;
    --quick) QUICK=1;;
    --strict) STRICT=1;;
    -h|--help) sed -n '2,15p' "$0"; exit 0;;
    *) echo "fatal: unknown flag $1" >&2; exit 1;;
  esac
  shift
done

cd "$(git rev-parse --show-toplevel)"
ROOT=$(pwd)

# repo-local scratch: the sandbox denies writes outside cwd, and macos mktemp ignores TMPDIR
TMPROOT="$ROOT/tmp"
mkdir -p "$TMPROOT"
FINDINGS=$(mktemp "$TMPROOT/settingsaudit-findings.XXXXXX")
SCRATCH=$(mktemp -d "$TMPROOT/settingsaudit-scratch.XXXXXX")
cleanup() { st=$?; if [ "$st" -eq 0 ]; then rm -rf "$FINDINGS" "$SCRATCH"; fi; }
trap cleanup EXIT

err()  { printf 'ERROR|%s|%s|%s\n' "$1" "$2" "$3" >> "$FINDINGS"; }
warn() { printf 'WARN|%s|%s|%s\n'  "$1" "$2" "$3" >> "$FINDINGS"; }
pass() { printf 'PASS|%s|%s|%s\n'  "$1" "$2" "$3" >> "$FINDINGS"; }

# the four scopes that carry a file; cli is session-only, so it is the one with nothing to read
MANAGED="/Library/Application Support/ClaudeCode/managed-settings.json"
SCOPES=("managed:$MANAGED" "local:$ROOT/.claude/settings.local.json" \
        "project:$ROOT/.claude/settings.json" "user:$HOME/.claude/settings.json")

# ==============
# STATIC - parse
#   an unparseable settings file is ignored in silence, so every rule in it stops existing
# ==============
check_parse() {
  local pair name path count
  for pair in "${SCOPES[@]}"; do
    name=${pair%%:*}
    path=${pair#*:}
    if [ ! -f "$path" ]; then continue; fi
    if jq empty "$path" >/dev/null 2>&1; then
      count=$(jq '[.permissions[]?|length]|add // 0' "$path")
      pass parse "$name" "parses, $count rules"
    else
      err parse "$name" "does not parse; every rule in this scope is silently inert"
    fi
  done
}

# ==============
# STATIC - drift
#   the template is the reviewed copy, the installed file is the one that actually runs
# ==============
check_drift() {
  local pair name path template missing extra
  for pair in "project:$ROOT/.claude/settings.json" "user:$HOME/.claude/settings.json"; do
    name=${pair%%:*}
    path=${pair#*:}
    template="$ROOT/AGENTS/settings/settings.$name.json"
    if [ ! -f "$path" ] || [ ! -f "$template" ]; then continue; fi
    # a rule set is what matters, never the order it was typed, so sort before comparing; a byte
    # diff calls a reordered pair drifted and buries the one line that actually went missing
    jq -S '(.permissions // {}) |= with_entries(.value |= sort)' "$template" \
      > "$SCRATCH/$name.a" 2>/dev/null || true
    jq -S '(.permissions // {}) |= with_entries(.value |= sort)' "$path" \
      > "$SCRATCH/$name.b" 2>/dev/null || true
    if diff -q "$SCRATCH/$name.a" "$SCRATCH/$name.b" >/dev/null 2>&1; then
      pass drift "$name" "installed copy carries the same rules as its template"
    else
      missing=$(diff "$SCRATCH/$name.a" "$SCRATCH/$name.b" | grep -c '^<' || true)
      extra=$(diff "$SCRATCH/$name.a" "$SCRATCH/$name.b" | grep -c '^>' || true)
      warn drift "$name" "${missing:-0} rules only in the template, ${extra:-0} only installed"
    fi
  done
}

# ==============
# STATIC - verbs
#   a Read deny is not a deny: the missing verbs stay safe only while no allow reaches them
# ==============
check_verbs() {
  local pair name path target verbs
  for pair in "${SCOPES[@]}"; do
    name=${pair%%:*}
    path=${pair#*:}
    if [ ! -f "$path" ] || ! jq empty "$path" >/dev/null 2>&1; then continue; fi
    jq -r '.permissions.deny[]? | select(test("^(Read|Write|Edit)\\("))' "$path" \
      | sed -E 's/^(Read|Write|Edit)\((.*)\)$/\2	\1/' | sort -u > "$SCRATCH/$name.verbs"
    while IFS= read -r target; do
      if [ -z "$target" ]; then continue; fi
      verbs=$(awk -F'\t' -v t="$target" '$1 == t { print $2 }' "$SCRATCH/$name.verbs" | tr '\n' ' ')
      case "$verbs" in
        *Write*) ;;
        *) err verbs "$name" "$target denied for read only; a write still reaches it";;
      esac
    done < <(cut -f1 "$SCRATCH/$name.verbs" | sort -u)
  done
}

# ==============
# STATIC - scope
#   machine detail in a committed file travels to strangers, and mask outside user is inert
# ==============
check_scope() {
  local project="$ROOT/.claude/settings.json" homey
  if [ ! -f "$project" ] || ! jq empty "$project" >/dev/null 2>&1; then return; fi

  if jq -e '.sandbox.credentials' "$project" >/dev/null 2>&1; then
    err scope project "carries credentials; mask is honored from user and managed only"
  else
    pass scope project "no credentials block, which this scope could not honor anyway"
  fi

  if jq -e '.sandbox.filesystem.allowWrite' "$project" >/dev/null 2>&1; then
    warn scope project "carries filesystem.allowWrite, which is this machine's detail"
  fi

  # a deny naming ~ protects the same path on any mac, so it travels; an allow naming ~ is this
  # machine's layout and means a clone inherits a grant pointing at a directory it does not have
  homey=$(jq -r '[.permissions.allow[]? | select(test("\\(~/"))] | length' "$project")
  if [ "$homey" -gt 0 ]; then
    warn scope project "$homey allow rules name a home path that differs on the next machine"
  fi
}

# ==============
# STATIC - hygiene
#   a duplicate is noise, and a comment below the first brace voids the file once pasted
# ==============
check_hygiene() {
  local pair path dupes template name
  for pair in "${SCOPES[@]}"; do
    name=${pair%%:*}
    path=${pair#*:}
    if [ ! -f "$path" ] || ! jq empty "$path" >/dev/null 2>&1; then continue; fi
    dupes=$(jq -r '.permissions[]?[]?' "$path" | sort | uniq -d | wc -l | tr -d ' ')
    if [ "$dupes" -gt 0 ]; then warn hygiene "$name" "$dupes duplicate rules"; fi
  done
  # the templates get the same checks as the installed copies: a duplicate here is what a paste
  # carries downstream, and it reads as drift against a clean install rather than as its own fault
  for template in "$ROOT"/AGENTS/settings/settings.*.json; do
    if [ ! -f "$template" ]; then continue; fi
    name=$(basename "$template")
    if ! jq empty "$template" >/dev/null 2>&1; then
      err hygiene "$name" "does not parse; a template that cannot be pasted is not a template"
      continue
    fi
    dupes=$(jq -r '.permissions[]?[]?' "$template" 2>/dev/null | sort | uniq -d | wc -l | tr -d ' ')
    if [ "${dupes:-0}" -gt 0 ]; then warn hygiene "$name" "$dupes duplicate rules"; fi
  done
}

# ==============
# STATIC - coverage
#   every rule earns a why, so the doc is checked against the json in both directions; a section
#   marked "mirrors <scope>" is an assertion rather than a shorthand, and gets diffed for real
# ==============
check_coverage() {
  local scope json doc section mirrored missing stale plus
  for scope in managed user project local; do
    json="$ROOT/AGENTS/settings/settings.$scope.json"
    doc="$ROOT/AGENTS/settings/settings.$scope.md"
    if [ ! -f "$json" ]; then continue; fi
    if [ ! -f "$doc" ]; then
      err coverage "$scope" "no settings.$scope.md; every scope file needs its reasoning"
      continue
    fi

    # a mirror claim is only true while the two sections still match, so test the claim itself; a
    # rule the claim covers needs no code span, which is the whole economy of the shorthand
    : > "$SCRATCH/$scope.mirrored"
    for section in allow ask deny; do
      # a grep that matches nothing is the normal case here, so every pipeline stays tolerant;
      # under pipefail an empty match would otherwise abort the whole audit with no output
      mirrored=$(sed -n "/^## permissions\.$section\$/,/^## /p" "$doc" \
        | grep -oE '^> mirrors [a-z]+' | awk '{print $3}' | head -n 1 || true)
      if [ -z "$mirrored" ]; then continue; fi
      plus=$(sed -n "/^## permissions\.$section\$/,/^## /p" "$doc" \
        | grep -cE '^> mirrors [a-z]+, plus' || true)
      jq -r ".permissions.${section}[]?" "$json" | sort -u > "$SCRATCH/$scope.$section"
      jq -r ".permissions.${section}[]?" \
        "$ROOT/AGENTS/settings/settings.$mirrored.json" 2>/dev/null | sort -u \
        > "$SCRATCH/$mirrored.$section.ref"
      cat "$SCRATCH/$mirrored.$section.ref" >> "$SCRATCH/$scope.mirrored"
      # "mirrors x" asserts the sets match; "mirrors x, plus" asserts x is contained, no more
      if [ "${plus:-0}" -gt 0 ]; then
        if [ "$(comm -23 "$SCRATCH/$mirrored.$section.ref" "$SCRATCH/$scope.$section" | wc -l)" -eq 0 ]
        then pass coverage "$scope" "permissions.$section still contains all of $mirrored"
        else err coverage "$scope" "permissions.$section claims to extend $mirrored but drops rules"
        fi
      elif diff -q "$SCRATCH/$scope.$section" "$SCRATCH/$mirrored.$section.ref" >/dev/null 2>&1; then
        pass coverage "$scope" "permissions.$section still mirrors $mirrored"
      else
        err coverage "$scope" "permissions.$section claims to mirror $mirrored but has diverged"
      fi
    done
    sort -u "$SCRATCH/$scope.mirrored" -o "$SCRATCH/$scope.mirrored"

    # every remaining rule has to appear as a code span, and every span has to still be a rule
    jq -r '.permissions[]?[]?' "$json" | sort -u > "$SCRATCH/$scope.rules"
    : > "$SCRATCH/$scope.documented"
    grep -oE '`(Read|Write|Edit|Bash|WebFetch|WebSearch)\([^`]*\)`' "$doc" \
      | tr -d '`' >> "$SCRATCH/$scope.documented" || true
    grep -oE '`(Read|Write|Edit|WebSearch)`' "$doc" \
      | tr -d '`' >> "$SCRATCH/$scope.documented" || true
    # the docs also quote rules inside fenced json blocks, exactly as the json files write them
    grep -oE '"(Read|Write|Edit|Bash|WebFetch|WebSearch)\([^"]*\)"' "$doc" \
      | tr -d '"' >> "$SCRATCH/$scope.documented" || true
    grep -oE '"(Read|Write|Edit|WebSearch)"' "$doc" \
      | tr -d '"' >> "$SCRATCH/$scope.documented" || true
    # a mirrored rule is already answered by the claim above, so it counts as covered
    cat "$SCRATCH/$scope.mirrored" >> "$SCRATCH/$scope.documented"
    sort -u "$SCRATCH/$scope.documented" -o "$SCRATCH/$scope.documented"
    missing=$(comm -23 "$SCRATCH/$scope.rules" "$SCRATCH/$scope.documented" | wc -l | tr -d ' ')
    stale=$(comm -13 "$SCRATCH/$scope.rules" "$SCRATCH/$scope.documented" | wc -l | tr -d ' ')
    if [ "${missing:-0}" -gt 0 ]; then
      err coverage "$scope" "$missing rules carry no why in settings.$scope.md"
    fi
    if [ "${stale:-0}" -gt 0 ]; then
      warn coverage "$scope" "$stale documented rules no longer exist in the json"
    fi
    if [ "${missing:-0}" -eq 0 ] && [ "${stale:-0}" -eq 0 ]; then
      pass coverage "$scope" "every rule documented, nothing stale"
    fi
  done
}

# ==============
# STATIC - guard
#   this file audits the boundary, so an agent that can rewrite it can make it report clean
# ==============
check_guard() {
  local project="$ROOT/.claude/settings.json" guarded hooked
  if [ ! -f "$project" ] || ! jq empty "$project" >/dev/null 2>&1; then return; fi
  guarded=$(jq -r '[(.permissions.deny[]?, .permissions.ask[]?)
    | select(test("AGENTS/(settings|hooks|\\*\\*)"))] | length' "$project")
  # the hook is the layer a settings edit cannot switch off, so report it as its own finding
  hooked=0
  if grep -q 'AGENTS/settings\|AGENTS/hooks' "$ROOT/AGENTS/hooks/pretooluse.sh" 2>/dev/null; then
    hooked=1
  fi
  if [ "$guarded" -eq 0 ] && [ "$hooked" -eq 0 ]; then
    warn guard project "nothing gates writes to AGENTS/settings or hooks; this auditor is editable"
  elif [ "$guarded" -eq 0 ]; then
    warn guard project "only pretooluse gates the policy directories; no settings rule backs it"
  else
    pass guard project "$guarded rules gate the policy directories"
  fi
}

# ==============
# LIVE - probes
#   inspection cannot find a latent fault; only exercising the protection can
# ==============
# the command arrives as arguments rather than a string, since eval is what the deny floor refuses
# and a sidecar reaching for it would be the exact bypass this file exists to report
probe() {
  local label=$1 expectation=$2 output
  shift 2
  output=$("$@" 2>&1 || true)
  if printf '%s' "$output" | grep -qiE "$expectation"; then
    pass probe "$label" "refused as configured"
  else
    err probe "$label" "not refused; got '${output:0:40}'"
  fi
}

check_probes() {
  local refusal='not permitted|denied|no such file|cannot open|refus' verdict token
  probe credential-read "$refusal" cat "$HOME/.operator/.env"
  probe ssh-key-read "$refusal" cat "$HOME/.ssh/id_rsa"

  # the hook is the failover the deny list leans on, so replay one string it has to refuse
  verdict=$(jq -n --arg c "git push --force origin main" '{tool_input:{command:$c}}' \
    | bash "$ROOT/AGENTS/hooks/pretooluse.sh" 2>/dev/null || true)
  if printf '%s' "$verdict" | grep -q '"permissionDecision"'; then
    pass probe force-push "the hook denies it, as the failover intends"
  else
    err probe force-push "the hook stayed silent on a force push"
  fi

  # mask hides the value from the sandbox while leaving it spendable, so a sentinel is the pass
  token=${GH_TOKEN:-}
  if [ -z "$token" ]; then
    warn probe token-mask "GH_TOKEN is unset here, so the mask cannot be observed"
  elif printf '%s' "$token" | grep -qE '^gh[pousr]_[A-Za-z0-9]{20,}'; then
    err probe token-mask "GH_TOKEN reads as a real token inside the sandbox"
  else
    pass probe token-mask "GH_TOKEN reads as a sentinel rather than the real value"
  fi
}

# ==============
# WRAPPED - the two sidecars that already answer their own question
# ==============
run_wrapped() {
  local name script output count
  for name in permissions scopes; do
    script="$HERE/$name.sh"
    if [ ! -f "$script" ]; then warn wrapped "$name" "no $name.sh beside this sidecar"; continue; fi
    output=$(bash "$script" 2>&1 || true)
    count=$(printf '%s' "$output" | sed -n 's/^errors: \([0-9]\{1,\}\)$/\1/p' | head -n 1)
    count=${count:-0}
    if [ "$count" -gt 0 ]; then
      err wrapped "$name" "$count errors; run AGENTS/settings/$name.sh for the detail"
    else
      pass wrapped "$name" "0 errors"
    fi
  done
}

# ==============
# EXECUTION
# ==============
check_parse
check_drift
check_verbs
check_scope
check_hygiene
check_coverage
check_guard
if [ "$STATIC_ONLY" -eq 0 ]; then check_probes; fi
if [ "$STATIC_ONLY" -eq 0 ] && [ "$QUICK" -eq 0 ]; then run_wrapped; fi

# ==============
# TELEMETRY
# ==============
ERRORS=$(grep -c '^ERROR|' "$FINDINGS" 2>/dev/null || true)
WARNINGS=$(grep -c '^WARN|' "$FINDINGS" 2>/dev/null || true)
PASSES=$(grep -c '^PASS|' "$FINDINGS" 2>/dev/null || true)
ERRORS=${ERRORS:-0}
WARNINGS=${WARNINGS:-0}
PASSES=${PASSES:-0}

TODAYS_AUDIT="docs/audits/$(date +%Y-%m-%d)-settings.md"
if [ -f "$ROOT/$TODAYS_AUDIT" ];
then AUDIT_COUNT=$(grep -c '^## Settings Audit #' "$ROOT/$TODAYS_AUDIT" || true)
else AUDIT_COUNT=0; fi
AUDIT_COUNT=${AUDIT_COUNT:-0}

cat <<EOF

=== settingsaudit.sh sidecar ===
audit_file: $TODAYS_AUDIT
audit_count: $AUDIT_COUNT
next_audit: $((AUDIT_COUNT + 1))
timestamp: $(date '+%Y-%m-%d %H:%M')
probes: $(if [ "$STATIC_ONLY" -eq 1 ]; then echo skipped; else echo run; fi)
passes: $PASSES
errors: $ERRORS
warnings: $WARNINGS
--- findings ---
EOF

# every check and its verdict, passes included: the artifact pastes this whole block, and a reader
# cannot tell a check that passed from one that never ran if only the failures are printed
sort -t'|' -k2,2 -k3,3 "$FINDINGS" \
  | awk -F'|' '{ printf "%-5s %-10s %-30s %s\n", $1, $2, $3, $4 }'

cat <<'EOF'
--- needs a human (rules no script can judge) ---
- a deny naming a path nothing on this disk holds is insurance, not a finding
- the probes prove today's boundary; an upgrade can move it without any file changing
- an allow this calls broad may be right, since the deny floor is what carries the weight
- a drift finding is a defect only when the installed copy is the stale one
================================
EOF

if [ "$ERRORS" -gt 0 ]; then exit 1; fi
if [ "$STRICT" -eq 1 ] && [ "$WARNINGS" -gt 0 ]; then exit 1; fi
exit 0

#!/bin/bash
# ==========================================================
# @file scopes.sh - workflow tester against a settings stack
# ==========================================================
# @description
# - maps a workflow script against a merged stack of settings files, without installing anything
# - the script file is the unit of trust, so every finding is reported under the script it came from
# - tier 1 replays the script's OWN invocation, the one string a permission rule actually sees
# - tier 2 extracts what the script runs internally, which no permission rule is ever shown
# - internals are judged against the sandbox alone, since that is the only layer still watching
# - a `deny` an internal would have tripped is reported as a bypass, not as a block
# - `--repo <name>` resolves a bare name under ~/Developer to that repo's own settings stack
# - `--strict` promotes warnings to errors, `--keep` preserves scratch; exits 1 on any error
# @see AGENTS.md, AGENTS/security/permissions.sh, AGENTS/security/corpus.tsv,
#      AGENTS/hooks/pretooluse.sh, AGENTS/settings/

set -euo pipefail

# ==============
# PREFLIGHT
# ==============
# the hook sits beside this file, not beside the repo under test: resolve it before any cd, since
# BASH_SOURCE arrives relative and would follow that cd to somewhere it does not exist
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)
HOOK="$HERE/../hooks/pretooluse.sh"
if [ ! -f "$HOOK" ]; then echo "fatal: no ../hooks/pretooluse.sh beside this script" >&2; exit 1; fi
if ! command -v jq >/dev/null 2>&1; then echo "fatal: jq is required and not installed" >&2; exit 1; fi

STRICT=0
KEEP=0
REPO=""
TARGETS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --strict) STRICT=1;;
    --keep) KEEP=1;;
    --repo) shift; REPO=${1:-}; if [ -z "$REPO" ]; then echo "fatal: --repo needs a name" >&2; exit 1; fi;;
    -h|--help) sed -n '2,15p' "$0"; exit 0;;
    -*) echo "fatal: unknown flag $1" >&2; exit 1;;
    *) TARGETS+=("$1");;
  esac
  shift
done

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "fatal: not a git repository" >&2; exit 1; fi
cd "$(git rev-parse --show-toplevel)"
SELF=$(pwd)

# a bare repo name beats a flag per repo, so resolve it under ~/Developer and test that stack
ROOT="$SELF"
if [ -n "$REPO" ]; then
  ROOT=$(find "$HOME/Developer" -maxdepth 3 -type d -name "$REPO" -print -quit 2>/dev/null || true)
  if [ -z "$ROOT" ]; then echo "fatal: no repo named '$REPO' under ~/Developer" >&2; exit 1; fi
fi

# precedence runs managed → cli → local → project → user
# cli is session-only, so it is the one scope with no file to read
MANAGED="/Library/Application Support/ClaudeCode/managed-settings.json"
STACK=()
STACK_NAMES=()
for pair in "managed:$MANAGED" "local:$ROOT/.claude/settings.local.json" \
            "project:$ROOT/.claude/settings.json" "user:$HOME/.claude/settings.json"; do
  name=${pair%%:*}
  path=${pair#*:}
  if [ -f "$path" ]; then STACK+=("$path"); STACK_NAMES+=("$name"); fi
done
if [ ${#STACK[@]} -eq 0 ]; then echo "fatal: no settings files found for $ROOT" >&2; exit 1; fi

# nothing was passed, so test every workflow script this repo ships
if [ ${#TARGETS[@]} -eq 0 ]; then
  while IFS= read -r found; do TARGETS+=("$found"); done < <(
    find "$SELF/AGENTS" -name '*.sh' -type f 2>/dev/null | sort
  )
fi
if [ ${#TARGETS[@]} -eq 0 ]; then echo "fatal: no scripts to test" >&2; exit 1; fi

# repo-local scratch: the sandbox denies writes outside cwd, and macos mktemp ignores TMPDIR
TMPROOT="$SELF/tmp"
TMPTAG=$(basename "${BASH_SOURCE[0]}" .sh)
mkdir -p "$TMPROOT"
FINDINGS=$(mktemp "$TMPROOT/$TMPTAG-findings.XXXXXX")
SCRATCH=$(mktemp -d "$TMPROOT/$TMPTAG-scratch.XXXXXX")
cleanup() { st=$?; if [ "$KEEP" -eq 0 ] && [ "$st" -eq 0 ]; then rm -rf "$FINDINGS" "$SCRATCH"; fi; }
trap cleanup EXIT

err()  { printf 'ERROR|%s|%s|%s|%s\n' "$1" "$2" "$3" "$4" >> "$FINDINGS"; }
warn() { printf 'WARN|%s|%s|%s|%s\n'  "$1" "$2" "$3" "$4" >> "$FINDINGS"; }

# ==============
# MERGE
#   arrays merge across every scope, so a rule is in force if any file in the stack carries it
# ==============
merge() {
  local filter=$1 file
  for file in "${STACK[@]}"; do
    jq -r "${filter}[]? // empty" "$file" 2>/dev/null || true
  done | sort -u
}
merge '.permissions.deny'            > "$SCRATCH/deny"
merge '.permissions.ask'             > "$SCRATCH/ask"
merge '.permissions.allow'           > "$SCRATCH/allow"
merge '.sandbox.filesystem.allowWrite' > "$SCRATCH/allowwrite"
merge '.sandbox.filesystem.denyRead'   > "$SCRATCH/denyread"
merge '.sandbox.network.allowedDomains' > "$SCRATCH/domains"
merge '.sandbox.excludedCommands'      > "$SCRATCH/excluded"

# a settings file that does not parse is a settings file the harness silently ignores
for i in "${!STACK[@]}"; do
  if ! jq empty "${STACK[$i]}" >/dev/null 2>&1; then
    err "${STACK_NAMES[$i]}" settings "${STACK[$i]}" "does not parse as json; these rules never load"
  fi
done

# the origin host is what a git network call actually resolves to, so read it rather than guess it
ORIGIN_HOST=$(git -C "$ROOT" remote get-url origin 2>/dev/null \
  | sed -E 's#^[a-z]+://##; s#^[^@/]*@##; s#^([^/:]*)[:/].*#\1#' || true)
if [ -z "$ORIGIN_HOST" ]; then ORIGIN_HOST="the origin host"; fi

# ==============
# TIER 1 — the invocation
#   this is the only string a permission rule is ever shown, so its verdict is exact
# ==============
T1_PASS=0; T1_ASK=0; T1_FAIL=0

# the hook answers in json or says nothing at all, and silence is the allow case
hook_verdict() {
  local cmd=$1 out
  out=$(jq -n --arg c "$cmd" '{tool_input:{command:$c}}' | bash "$HOOK" 2>/dev/null || true)
  if [ -z "$out" ]; then printf 'silent'; else printf 'deny'; fi
}

# every internal is tested against every rule, so the lists load once rather than per call
DENY_RULES=(); ASK_RULES=(); ALLOW_RULES=()
load_rules() {
  local list=$1 rule pattern
  while IFS= read -r rule; do
    case "$rule" in Bash\(*\)) ;; *) continue;; esac
    pattern=${rule#Bash(}
    pattern=${pattern%)}
    case "$list" in
      deny)  DENY_RULES+=("$pattern");;
      ask)   ASK_RULES+=("$pattern");;
      allow) ALLOW_RULES+=("$pattern");;
    esac
  done < "$SCRATCH/$list"
}
load_rules deny; load_rules ask; load_rules allow

# a rule matches exactly what was written, so the pattern stays unquoted and globs as authored
hits_deny() {
  local p; if [ ${#DENY_RULES[@]} -eq 0 ]; then return 1; fi
  # shellcheck disable=SC2254 # globbing is the point: a rule matches as authored
  for p in "${DENY_RULES[@]}"; do case "$1" in $p) return 0;; esac; done; return 1
}
hits_ask() {
  local p; if [ ${#ASK_RULES[@]} -eq 0 ]; then return 1; fi
  # shellcheck disable=SC2254 # globbing is the point: a rule matches as authored
  for p in "${ASK_RULES[@]}"; do case "$1" in $p) return 0;; esac; done; return 1
}
hits_allow() {
  local p; if [ ${#ALLOW_RULES[@]} -eq 0 ]; then return 1; fi
  # shellcheck disable=SC2254 # globbing is the point: a rule matches as authored
  for p in "${ALLOW_RULES[@]}"; do case "$1" in $p) return 0;; esac; done; return 1
}

tier1() {
  local script=$1 rel call
  rel=${script#"$SELF"/}
  call="$rel"
  if [ "$(hook_verdict "$call")" = "deny" ]; then
    err "$rel" invocation "$call" "the hook blocks this script from running at all"
    T1_FAIL=$((T1_FAIL + 1)); return
  fi
  if hits_deny "$call"; then
    err "$rel" invocation "$call" "a deny rule refuses the script; no allow can override it"
    T1_FAIL=$((T1_FAIL + 1)); return
  fi
  if hits_ask "$call"; then
    warn "$rel" invocation "$call" "an ask rule prompts every run, even sandboxed"
    T1_ASK=$((T1_ASK + 1)); return
  fi
  if hits_allow "$call"; then
    T1_PASS=$((T1_PASS + 1)); return
  fi
  warn "$rel" invocation "$call" "no allow rule names it, so every run prompts; add one in project"
  T1_ASK=$((T1_ASK + 1))
}

# ==============
# TIER 2 — the internals
#   a script's own commands are not tool calls, so permissions never see them; the sandbox does
# ==============
T2_SEEN=0

# strip comments, then split on every separator that starts a fresh command
internals_of() {
  local file=$1
  sed -E 's/^[[:space:]]*#.*$//' "$file" \
    | sed -E 's/[[:space:]]#[[:space:]].*$//' \
    | tr ';|&' '\n\n\n' \
    | sed -E 's/\$\(/\n/g; s/`/\n/g' \
    | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' \
    | sed -E 's/^(if|then|else|elif|fi|for|while|do|done|case|esac|!|not)[[:space:]]+//' \
    | grep -vE '^$' || true
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

# only a call that leaves the working directory or the machine can trip a sandbox layer
NETWORK='^(gh|curl|wget|npx|npm|pnpm|yarn)$|^git (fetch|push|pull|clone|ls-remote|remote|submodule)$'
WRITERS='^(rm|cp|mv|tee|mkdir|touch|chmod|chown|ln|install|rsync|dd)$'

# a path outside the working directory is what the filesystem layer judges, so collect those only
outside_paths() {
  local line=$1 token
  for token in $line; do
    case "$token" in
      /*|~/*) printf '%s\n' "$token";;
    esac
  done
  printf '%s' "$line" | grep -oE '>>?[[:space:]]*[^[:space:]]+' 2>/dev/null \
    | sed -E 's/^>>?[[:space:]]*//' | grep -E '^(/|~/)' || true
}

covered_by() {
  local list=$1 path=$2 entry stem
  while IFS= read -r entry; do
    if [ -z "$entry" ]; then continue; fi
    stem=${entry%/**}
    stem=${stem%\*}
    case "$path" in "$stem"*) return 0;; esac
  done < "$SCRATCH/$list"
  return 1
}

tier2() {
  local script=$1 rel line base path host
  rel=${script#"$SELF"/}
  while IFS= read -r line; do
    if [ -z "$line" ]; then continue; fi
    base=$(base_of "$line")
    case "$base" in ''|[A-Z_]*=*|\[*|echo|printf|return|exit|local|shift|set|trap|read) continue;; esac
    T2_SEEN=$((T2_SEEN + 1))

    # a deny that would have caught this string never fires, because no rule is consulted here
    if hits_deny "$line" || hits_deny "$base"; then
      err "$rel" bypass "$base" "a deny names this, but an internal call is not a tool call"
      continue
    fi

    # excluded commands run outside the sandbox, so neither layer is watching them at all
    if grep -qE "^$(printf '%s' "$base" | awk '{print $1}') ?\*?$" "$SCRATCH/excluded" 2>/dev/null; then
      warn "$rel" excluded "$base" "runs unsandboxed via excludedCommands; only the hook remains"
      continue
    fi

    # domain layer: an unlisted host prompts, and a prompt inside a script stalls rather than asks
    if printf '%s' "$base" | grep -qE "$NETWORK"; then
      host="$ORIGIN_HOST"
      case "$base" in npm*|pnpm*|yarn*|npx*) host="registry.npmjs.org";; esac
      if ! grep -qxF "$host" "$SCRATCH/domains" 2>/dev/null; then
        err "$rel" domain "$base" "reaches $host, unlisted; add it to allowedDomains in project"
      fi
    fi

    # a line naming no path cannot trip either path layer, so skip the scan rather than spawn for it
    case "$line" in */*|*~*) ;; *) continue;; esac

    # filesystem layer: a write outside cwd is denied by default, and the failure reads as a bug
    if printf '%s' "$base" | grep -qE "$WRITERS"; then
      while IFS= read -r path; do
        if [ -z "$path" ]; then continue; fi
        case "$path" in "$SELF"/*|./*) continue;; esac
        if ! covered_by allowwrite "$path"; then
          err "$rel" filesystem "$base" "writes $path outside cwd; add it to allowWrite in user"
        fi
      done < <(outside_paths "$line")
    fi

    # a denied read still applies to bash, so a script reading one fails where a human would not
    while IFS= read -r path; do
      if [ -z "$path" ]; then continue; fi
      if covered_by denyread "$path"; then
        warn "$rel" read "$base" "reads $path, which denyRead blocks for sandboxed bash"
      fi
    done < <(outside_paths "$line")
  done < <(internals_of "$script")
}

for target in "${TARGETS[@]}"; do
  if [ ! -f "$target" ]; then warn "$target" missing "" "no such file; skipped"; continue; fi
  tier1 "$target"
  tier2 "$target"
done

# ==============
# TELEMETRY
# ==============
ERRORS=$(sort -u "$FINDINGS" | grep -c "^ERROR|" 2>/dev/null || true)
WARNINGS=$(sort -u "$FINDINGS" | grep -c '^WARN|' 2>/dev/null || true)
ERRORS=${ERRORS:-0}
WARNINGS=${WARNINGS:-0}

cat <<EOF

=== scopes.sh workflow tester ===
repo: $ROOT
stack: ${STACK_NAMES[*]}
origin: $ORIGIN_HOST
scripts: ${#TARGETS[@]}
invocations: $T1_PASS allowed, $T1_ASK prompting, $T1_FAIL refused
internals: $T2_SEEN inspected, none of which cross a permission gate
errors: $ERRORS
warnings: $WARNINGS
--- findings ---
EOF

if [ "$ERRORS" -eq 0 ] && [ "$WARNINGS" -eq 0 ]; then
  echo "none — every script runs, and every internal stays inside the merged boundary"
else
  # one script calling the same command twice is one finding, so identical rows collapse
  sort -u -t'|' -k2,2 -k3,3 -k4,4 "$FINDINGS" \
    | awk -F'|' '{ printf "%-5s %-34s %-11s %-22s %s\n", $1, $2, $3, substr($4, 1, 20), $5 }'
fi

cat <<'EOF'
--- what this tester cannot tell you ---
- it reads scripts, it never runs them, so a command built at runtime is invisible to it
- a quoted path and a variable path look the same here; expanded values are not resolved
- it names one host per call from the repo's origin, so a second remote is not modelled
- managed is only in the stack if it is installed; a missing ceiling reads as a permissive one
- the sandbox decides at the kernel, so treat every filesystem verdict as a prediction to test
- an internal reported clean is clean against these files, not against the ones that ship
=================================
EOF

if [ "$ERRORS" -gt 0 ]; then exit 1; fi
if [ "$STRICT" -eq 1 ] && [ "$WARNINGS" -gt 0 ]; then exit 1; fi
exit 0

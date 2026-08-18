#!/bin/bash
# ==========================================================
# @file scripts.sh - what a script runs versus your settings
# ==========================================================
# @description
# PAIR
# - sidecar for `/operator:scripts` — tests what a workflow script runs against the merged settings
# - it answers what the floor cannot: what a sidecar reaches once it is already running
# - it installs nothing, and the script file is the unit of trust every finding reports under
# TIERS
# - tier 1 replays the script's OWN invocation, the one string a permission rule actually sees
# - tier 2 extracts what the script runs internally, which no permission rule is ever shown
# - internals are judged against the sandbox alone, since that is the only layer still watching
# - a `deny` an internal would have tripped is reported as a bypass, not as a block
# RUN
# - read-only: it maps and reports, and every repair is the user's to apply
# - `--repo <name>` resolves a bare name under ~/Developer to that repo's own settings stack
# - `--strict` promotes warnings to errors, `--keep` preserves scratch; exits 1 on any error
# - the slowest trigger in the family, since it spawns the hook once per extracted command
# @see plugins/operator/skills/scripts/SKILL.md, plugins/operator/hooks/pretooluse/, plugins/operator/shared/corpus.tsv, plugins/operator/settings/settings.user.md, plugins/operator/skills/settings/SKILL.md

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
# the hook sits beside this file, not beside the repo under test: resolve it before any cd, since
# BASH_SOURCE arrives relative and would follow that cd to somewhere it does not exist
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)
HOOKS="$HERE/../../hooks/pretooluse"
if [ ! -d "$HOOKS" ]; then echo "fatal: no plugins/operator/hooks/pretooluse/ reachable" >&2; exit 1; fi
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
    find "$SELF/plugins" "$SELF/.claude/skills" -name '*.sh' -type f 2>/dev/null | sort
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

# an action answers in json or says nothing at all, and silence from every one is the allow case
hook_verdict() {
  local cmd=$1 action out
  for action in "$HOOKS"/*.sh; do
    out=$(jq -n --arg c "$cmd" '{tool_input:{command:$c}}' | bash "$action" 2>/dev/null || true)
    if [ -n "$out" ]; then printf 'deny'; return; fi
  done
  printf 'silent'
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
T2_BYPASS=0

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
      T2_BYPASS=$((T2_BYPASS + 1))
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
# ARTIFACT
#   this skill's own dated artifact, graded here so nothing outside this file decides its shape
#   the shape lives in this skill's SKILL.md and the labels below are what this sidecar emits
# ==============
ARTIFACT_KIND="scripts"
ARTIFACT_SECTIONS=$'state\nfindings\nresolutions\ntelemetry'
ARTIFACT_LABELS='Bypass|Prompting|Unguarded Internal|Drift|Scope|Coverage'
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

check_artifact ".construct/operator/scripts"

# ==============
# TELEMETRY
# ==============
ERRORS=$(sort -u "$FINDINGS" | grep -c "^ERROR|" 2>/dev/null || true)
WARNINGS=$(sort -u "$FINDINGS" | grep -c '^WARN|' 2>/dev/null || true)
ERRORS=${ERRORS:-0}
WARNINGS=${WARNINGS:-0}

# audit: one file per day per kind, so two triggers on the same day never interleave one file
# reported, never created: the sidecar names the path and the count, the agent writes the entry
AUDIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
TODAYS_AUDIT=".construct/operator/scripts/$(date +%Y-%m-%d).md"
if [ -f "$AUDIT_ROOT/$TODAYS_AUDIT" ];
then AUDIT_COUNT=$(grep -c '^## Scripts Audit #' "$AUDIT_ROOT/$TODAYS_AUDIT" || true)
else AUDIT_COUNT=0; fi
AUDIT_COUNT=${AUDIT_COUNT:-0}



cat <<EOF

=== scripts.sh workflow tester ===
audit_file: $TODAYS_AUDIT
audit_count: $AUDIT_COUNT
next_audit: $((AUDIT_COUNT + 1))
timestamp: $(date '+%Y-%m-%d %H:%M')
repo: $ROOT
stack: ${STACK_NAMES[*]}
origin: $ORIGIN_HOST
scripts: ${#TARGETS[@]}
invocations: $T1_PASS allowed, $T1_ASK prompting, $T1_FAIL refused
internals: $T2_SEEN inspected, $T2_BYPASS of which cross a permission gate
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


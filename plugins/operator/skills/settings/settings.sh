#!/bin/bash
# =====================================================
# @file settings.sh - settings stack auditor and prober
# =====================================================
# @description
# PAIR
# - sidecar for `/operator:settings` — audits the settings stack, then probes it live
# - safe anytime: read-only by contract, since every fix is the user's to make
# - a latent fault is the failure it exists for: protection that stopped working in silence
# CHECKS
# - STATIC checks read the files: parse, drift, verb symmetry, scope placement, hygiene, coverage
# - `guard` is the check that watches this auditor, since an editable auditor can be made to pass
# - LIVE probes exercise the boundary, because a config can be perfect while the gate is dead
# - it wraps the permissions and scopes replays rather than replacing them, surfacing error counts
# - a tracked path reads as guarded at `ask`, since `deny` reaches the sandbox and blocks git itself
# - templates resolve from the plugin, so drift and hygiene run the same under either install method
# RUN
# - a bare run prints its own usage, since the full audit takes minutes and reads as a hung session
# - `--audit` runs everything, `--static` skips the probes, `--quick` skips the wrapped sidecars
# - `--strict` fails on warnings, and each slow stage reports the seconds it spent
# - the doc appends one entry to the day's settings audit, never editing an earlier one
# EMIT
# - `--local`, `--project`, `--user` and `--managed` emit that scope's setup instead of auditing
# - `--advanced` walks the masked-credential setup, grading the user scope it can read
# - the env file is deny-listed, so not seeing it is the pass rather than a finding
# - an emit run never appends to the artifact, since these lines carry absolute home paths
# - it emits and never applies, because the deny floor stops this sidecar writing a settings file
# @see plugins/operator/skills/settings/SKILL.md, plugins/operator/skills/permissions/permissions.sh, plugins/operator/skills/scopes/scopes.sh, .operator/settings/

set -euo pipefail

# ==============
# PREFLIGHT
# ==============
# the shared scan sits in the settings tree, not beside this file and not beside the repo being
# audited: resolve both before any cd, since BASH_SOURCE arrives relative and would follow that cd
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)
SHARED=$(cd "$HERE/../../shared" 2>/dev/null && pwd || true)
if [ ! -f "$SHARED/secrets.sh" ]; then
  echo "fatal: no shared/secrets.sh reachable from this sidecar" >&2; exit 1; fi
# shellcheck source=../../shared/secrets.sh
. "$SHARED/secrets.sh"

# resolved from this file, never from the repo being audited: cwd holds no plugins/operator/ once
# the plugin is installed from a marketplace
TEMPLATES=${CLAUDE_PLUGIN_ROOT:-$(cd "$HERE/../.." 2>/dev/null && pwd || true)}/settings

AUDIT=0
STATIC_ONLY=0
QUICK=0
STRICT=0
ADVANCED=0
EMIT=()
# the audit modifiers imply the audit, since none of them mean anything on their own
while [ $# -gt 0 ]; do
  case "$1" in
    --audit) AUDIT=1;;
    --static) STATIC_ONLY=1; AUDIT=1;;
    --quick) QUICK=1; AUDIT=1;;
    --strict) STRICT=1; AUDIT=1;;
    --local|--project|--user|--managed) EMIT+=("${1#--}");;
    --advanced) ADVANCED=1;;
    -h|--help) AUDIT=0; EMIT=();;
    *) echo "fatal: unknown flag $1" >&2; exit 1;;
  esac
  shift
done

# a bare run explains itself rather than starting the slowest path by accident: the full audit runs
# for minutes, which reads as a hung session
if [ "$AUDIT" -eq 0 ] && [ "$ADVANCED" -eq 0 ] && [ ${#EMIT[@]} -eq 0 ]; then
  cat <<'EOF'

=== settings.sh sidecar (usage) ===
this sidecar audits the settings stack, or emits the setup for one scope. it never writes a
settings file: the deny floor stops it, so every command is handed back for you to run.

AUDIT
  --audit     every static check, the live probes, and the wrapped permissions and scopes runs
              slowest path by far, since the wrapped sidecars replay their whole corpus
  --static    the file checks only: parse, templates, drift, verbs, scope, hygiene, coverage, guard
  --quick     audit and probe, but skip the two wrapped sidecars
  --strict    exit non-zero on warnings as well as errors
  an audit appends one entry to .operator/settings/<today>.md

EMIT
  --local     the scope you alone see in this repo
  --project   the scope every collaborator on this repo inherits
  --user      your scope across every project
  --managed   the machine scope, which needs sudo and sits outside the project
  flags combine, and an emit run is never appended to the artifact

WALKTHROUGH
  --advanced  the masked-credential setup, step by step: the key directory, the env file, the deny
              rule, one mask rule per token, the domains those tokens reach, and the proof
              it grades the user scope it can read, and names the steps it cannot see

RELATED
  /operator:credentials   proves each token is masked, across every exfiltration vector
  /operator:permissions   replays the corpus through the real hook
  /operator:scopes        maps what a script reaches once it is already running
========================
EOF
  exit 0
fi

if ! command -v jq >/dev/null 2>&1; then echo "fatal: jq is required" >&2; exit 1; fi
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "fatal: not a git repository" >&2; exit 1; fi

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
# EMIT - scope setup
#   the audit grades what landed; this hands back the commands that land it
# ==============
target_of() {
  case "$1" in
    local)   printf '%s' "$ROOT/.claude/settings.local.json";;
    project) printf '%s' "$ROOT/.claude/settings.json";;
    user)    printf '%s' "$HOME/.claude/settings.json";;
    managed) printf '%s' "$MANAGED";;
  esac
}

# an absent target copies clean; a populated one is a merge, and saying so beats a lost rule set
state_of() {
  local path=$1 rules
  if [ ! -f "$path" ]; then printf 'absent, so the copy lands clean'; return 0; fi
  if ! jq empty "$path" >/dev/null 2>&1; then
    printf 'present but unparseable, so read it before overwriting'; return 0; fi
  rules=$(jq '[.permissions[]?|length]|add // 0' "$path")
  printf 'present with %s rule%s, so merge rather than overwrite' \
    "$rules" "$(if [ "$rules" -eq 1 ]; then echo ''; else echo s; fi)"
}

emit_scopes() {
  local scope template path missing=0
  printf '\n=== settings.sh sidecar (emit) ===\n'
  printf 'templates: %s\n' "$TEMPLATES"
  printf 'scopes: %s\n' "${EMIT[*]}"
  for scope in "${EMIT[@]}"; do
    template="$TEMPLATES/settings.$scope.json"
    path=$(target_of "$scope")
    printf -- '--- %s ---\n' "$scope"
    if [ ! -f "$template" ]; then
      printf 'template   MISSING at %s\n' "$template"
      missing=$((missing + 1))
      continue
    fi
    printf 'target     %s\n' "$path"
    printf 'state      %s\n' "$(state_of "$path")"
    if [ "$scope" = managed ]; then
      printf 'command    sudo mkdir -p "%s"\n' "$(dirname "$MANAGED")"
      printf '           sudo cp "%s" "%s"\n' "$template" "$path"
    else
      printf 'command    mkdir -p "%s"\n' "$(dirname "$path")"
      printf '           cp "%s" "%s"\n' "$template" "$path"
    fi
  done
  # not a copy, so no template carries them and no audit can hand them back
  cat <<EOF
--- beyond the copies (masked credentials) ---
keys       mkdir -p ~/.operator && chmod 700 ~/.operator
env        write each token into ~/.operator/.env as: export GH_TOKEN="..."
shell      append to ~/.zshrc: [ -r ~/.operator/.env ] && source ~/.operator/.env
rules      add one {"name":"GH_TOKEN","mode":"mask"} per token to sandbox.credentials.envVars
restart    restart the editor, then start a new claude session
EOF
  cat <<'EOF'
--- needs a human (rules no script can judge) ---
- every template is a starting point, since only you know which services you actually reach
- a copy onto a populated scope is a merge; the rules already there were put there for a reason
- rerun with no flag once the copies land, and /operator:credentials once tokens are masked
- an emit run is never appended to the artifact, since the paths above are machine detail
========================
EOF
  [ "$missing" -eq 0 ]
}

if [ ${#EMIT[@]} -gt 0 ]; then
  emit_scopes || exit 1
  exit 0
fi

# ==============
# EMIT - masked credentials
#   user scope holds the credentials, so this reads the installed user file and never a template
# ==============
# the mask rule and the domain list are two halves of one setup: a masked token whose host never
# reaches allowedDomains is authenticated against a host the sandbox refuses to resolve
advanced_state() {
  local installed=$1 masked domains host name gap=0
  masked=$(jq -r '[.sandbox.credentials.envVars[]? | select(.mode=="mask") | .name] | join(" ")' \
    "$installed" 2>/dev/null || true)
  domains=$(jq -r '[.sandbox.network.allowedDomains[]?] | join(" ")' "$installed" 2>/dev/null || true)
  if [ -z "$masked" ]; then
    printf 'masked     none yet, so step 7 is where this starts\n'
  else
    printf 'masked     %s\n' "$masked"
  fi
  # every injectHosts host has to appear in allowedDomains, or the token cannot reach its api
  for name in $masked; do
    while IFS= read -r host; do
      [ -n "$host" ] || continue
      case " $domains " in
        *" $host "*) ;;
        *) printf 'gap        %s injects into %s, which allowedDomains omits\n' "$name" "$host"
           gap=$((gap + 1));;
      esac
    done < <(jq -r --arg n "$name" \
      '.sandbox.credentials.envVars[]? | select(.name==$n) | .injectHosts[]?' "$installed" 2>/dev/null)
  done
  if [ -n "$masked" ] && [ "$gap" -eq 0 ]; then
    printf 'domains    every injected host is in allowedDomains\n'
  fi
  if jq -e '.sandbox.credentials.files[]? | select(.path|test("\\.operator/\\.env$"))' \
    "$installed" >/dev/null 2>&1; then
    printf 'deny       the env file is denied, so no agent reads it back\n'
  else
    printf 'deny       NO deny rule for ~/.operator/.env, so step 3 comes before any token\n'
  fi
}

emit_advanced() {
  local installed="$HOME/.claude/settings.json"
  printf '\n=== settings.sh sidecar (advanced) ===\n'
  printf 'scope      user, at %s\n' "$installed"
  if [ -d "$HOME/.operator" ]; then
    printf 'keydir     present, mode %s\n' "$(stat -f '%Lp' "$HOME/.operator" 2>/dev/null || echo '?')"
  else
    printf 'keydir     absent, so step 1 is where this starts\n'
  fi
  # the env file is deny-listed, so this sidecar cannot see it: not seeing it IS the pass
  printf 'envfile    not observable from here, which is the deny rule working\n'
  if [ -f "$installed" ] && jq empty "$installed" >/dev/null 2>&1; then
    advanced_state "$installed"
  else
    printf 'masked     no parseable user scope yet, so run --user first\n'
  fi
  cat <<'EOF'
--- steps, in this order (each one is yours to run) ---
1  keydir    mkdir -p ~/.operator && chmod 700 ~/.operator
2  envfile   touch ~/.operator/.env && chmod 600 ~/.operator/.env
3  deny      add {"path":"~/.operator/.env","mode":"deny"} to sandbox.credentials.files
             this lands BEFORE any token does, so the file is never briefly readable
4  unset     add {"name":"<VAR>","mode":"deny"} per exposed credential to
             sandbox.credentials.envVars, which removes the variable rather than hiding it
5  rotate    rotate each exposed token one at a time, since a token an agent could read is spent
6  export    append one line per rotated credential: export GH_TOKEN="..."
7  mask      add {"name":"GH_TOKEN","mode":"mask","injectHosts":["api.github.com"]} to
             sandbox.credentials.envVars, naming every host that token authenticates against
8  domains   add each injectHosts host to sandbox.network.allowedDomains
9  shell     append to ~/.zshrc: [ -r ~/.operator/.env ] && source ~/.operator/.env
10 restart   restart the editor, then start a new claude session
11 prove     run /operator:credentials, which spends each token and then tries to read it back
--- needs a human (rules no script can judge) ---
- only you know which services a token reaches, so only you can name its injectHosts
- a token with no injectHosts is inert under mask: it is hidden and it authenticates nothing
- masking is not recall, so step 5 comes first: a leaked value stays leaked behind a mask
- prefer deny over mask for a credential no command here needs, since deny removes the variable
- steps 6 and 9 write files this sidecar is denied, so nothing here can confirm them
========================
EOF
}

if [ "$ADVANCED" -eq 1 ]; then
  emit_advanced
  exit 0
fi

# ==============
# STATIC - templates
#   drift and hygiene both read this directory, so its absence is the finding that hides theirs
# ==============
check_templates() {
  local count
  if [ ! -d "$TEMPLATES" ]; then
    err templates missing "no settings/ beside this plugin; drift and hygiene read nothing"
    return 0
  fi
  count=$(find "$TEMPLATES" -maxdepth 1 -name 'settings.*.json' | wc -l | tr -d ' ')
  if [ "$count" -eq 0 ]; then
    err templates empty "settings/ holds no settings.*.json; drift and hygiene read nothing"
  else
    pass templates found "$count templates readable at the plugin root"
  fi
}

# ==============
# STATIC - drift
#   the template is the reviewed copy, the installed file is the one that actually runs
# ==============
check_drift() {
  local pair name path template missing extra
  # every scope that carries a file, not just the two shared ones: local and managed drifted in
  # silence while nothing compared them
  for pair in "${SCOPES[@]}"; do
    name=${pair%%:*}
    path=${pair#*:}
    template="$TEMPLATES/settings.$name.json"
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
  for template in "$TEMPLATES"/settings.*.json; do
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
    json="$ROOT/plugins/operator/settings/settings.$scope.json"
    doc="$ROOT/plugins/operator/settings/settings.$scope.md"
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
        "$ROOT/plugins/operator/settings/settings.$mirrored.json" 2>/dev/null | sort -u \
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
    | select(test("plugins/(operator/(settings|hooks)|\\*\\*)"))] | length' "$project")
  # the hook is the layer a settings edit cannot switch off, so report it as its own finding
  hooked=0
  if grep -q 'plugins/operator/settings\|plugins/operator/hooks' "$ROOT/plugins/operator/hooks/pretooluse.sh" 2>/dev/null; then
    hooked=1
  fi
  if [ "$guarded" -eq 0 ] && [ "$hooked" -eq 0 ]; then
    warn guard project "nothing gates writes to plugins/operator settings or hooks; this auditor is editable"
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
    | bash "$ROOT/plugins/operator/hooks/pretooluse.sh" 2>/dev/null || true)
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
# each wrapped tool is its own skill now, so it resolves through the sibling folder rather than by
# sitting beside this file; a missing one warns instead of failing, since the static half still ran
run_wrapped() {
  local name script output count started elapsed
  for name in permissions scopes; do
    script="$HERE/../$name/$name.sh"
    if [ ! -f "$script" ]; then warn wrapped "$name" "no $name.sh in its sibling skill folder"; continue; fi
    started=$SECONDS
    output=$(bash "$script" 2>&1 || true)
    elapsed=$((SECONDS - started))
    count=$(printf '%s' "$output" | sed -n 's/^errors: \([0-9]\{1,\}\)$/\1/p' | head -n 1)
    count=${count:-0}
    if [ "$count" -gt 0 ]; then
      err wrapped "$name" "$count errors in ${elapsed}s; run /operator:$name for the detail"
    else
      pass wrapped "$name" "0 errors in ${elapsed}s"
    fi
  done
}

# ==============
# EXECUTION
# ==============
check_parse
check_templates
check_drift
check_verbs
check_scope
check_hygiene
check_coverage
check_guard
# each slow stage reports its own elapsed seconds, since a run with no clock reads as a hung one
PROBES_ELAPSED=skipped
WRAPPED_ELAPSED=skipped
if [ "$STATIC_ONLY" -eq 0 ]; then
  STAGE_START=$SECONDS
  check_probes
  PROBES_ELAPSED="run in $((SECONDS - STAGE_START))s"
fi
if [ "$STATIC_ONLY" -eq 0 ] && [ "$QUICK" -eq 0 ]; then
  STAGE_START=$SECONDS
  run_wrapped
  WRAPPED_ELAPSED="run in $((SECONDS - STAGE_START))s"
fi

# ==============
# ARTIFACT
#   this skill's own dated artifact, graded here so nothing outside this file decides its shape
#   the shape lives in this skill's SKILL.md and the labels below are what this sidecar emits
# ==============
ARTIFACT_KIND="settings"
ARTIFACT_SECTIONS=$'state\nfindings\nresolutions\ntelemetry'
ARTIFACT_LABELS='Parse|Drift|Verbs|Scope|Hygiene|Coverage|Guard|Probe|Wrapped'
ARTIFACT_MAX_WIDTH=100

# this sidecar reports "category|scope|detail", so location folds into the scope field. passing
# four arguments to a three-field reporter is what silently dropped every detail before
artifact_err()  { err "$3" "$1:$2" "$4"; }
artifact_warn() { warn "$3" "$1:$2" "$4"; }

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

check_artifact ".operator/settings"

# ==============
# TELEMETRY
# ==============
ERRORS=$(grep -c '^ERROR|' "$FINDINGS" 2>/dev/null || true)
WARNINGS=$(grep -c '^WARN|' "$FINDINGS" 2>/dev/null || true)
PASSES=$(grep -c '^PASS|' "$FINDINGS" 2>/dev/null || true)
ERRORS=${ERRORS:-0}
WARNINGS=${WARNINGS:-0}
PASSES=${PASSES:-0}

TODAYS_AUDIT=".operator/settings/$(date +%Y-%m-%d).md"
if [ -f "$ROOT/$TODAYS_AUDIT" ];
then AUDIT_COUNT=$(grep -c '^## Settings Audit #' "$ROOT/$TODAYS_AUDIT" || true)
else AUDIT_COUNT=0; fi
AUDIT_COUNT=${AUDIT_COUNT:-0}



cat <<EOF

=== settings.sh sidecar ===
audit_file: $TODAYS_AUDIT
audit_count: $AUDIT_COUNT
next_audit: $((AUDIT_COUNT + 1))
timestamp: $(date '+%Y-%m-%d %H:%M')
probes: $PROBES_ELAPSED
wrapped: $WRAPPED_ELAPSED
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


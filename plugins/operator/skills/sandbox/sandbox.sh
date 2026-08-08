#!/bin/bash
# ==========================================
# @file sandbox.sh - sandbox setup emitter
# ==========================================
# @description
# PAIR
# - sidecar for `/operator:sandbox` — hands back the setup this plugin cannot perform itself
# - safe anytime: it reads and prints, since the deny floor stops a sidecar writing a settings file
# - the failure it exists for is a guessed path: the templates move with the install method
# EMITS
# - one copy command per scope, with both paths already resolved on the disk it ran on
# - the target's state beside each command, so an overwrite is never a surprise
# - the steps no copy covers: the key directory, the shell hook, and the restart
# RUN
# - no flag emits every scope; `--local`, `--project`, `--user` and `--managed` narrow it
# - `/operator:settings` grades what landed here, so run that after the copies, never before
# @see plugins/operator/skills/sandbox/SKILL.md, plugins/operator/skills/settings/settings.sh, plugins/operator/settings/
set -euo pipefail

# ==============
# PREFLIGHT
# ==============
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)

# resolved from this file, never from the project being set up: cwd holds no plugins/operator/ once
# the plugin is installed from a marketplace
TEMPLATES=${CLAUDE_PLUGIN_ROOT:-$(cd "$HERE/../.." 2>/dev/null && pwd || true)}/settings

if ! command -v jq >/dev/null 2>&1; then echo "fatal: jq is required" >&2; exit 1; fi

WANT=()
while [ $# -gt 0 ]; do
  case "$1" in
    --local|--project|--user|--managed) WANT+=("${1#--}");;
    -h|--help) sed -n '2,15p' "$0"; exit 0;;
    *) echo "fatal: unknown flag $1" >&2; exit 1;;
  esac
  shift
done
if [ ${#WANT[@]} -eq 0 ]; then WANT=(local project user managed); fi

# the project root is where a local or project scope lands; outside a repo it is just the cwd, since
# a reader can configure a plain directory
ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)

MANAGED="/Library/Application Support/ClaudeCode/managed-settings.json"

# ==============
# TARGETS
#   each scope names the file it installs to, and only the managed one needs sudo to get there
# ==============
target_of() {
  case "$1" in
    local)   printf '%s' "$ROOT/.claude/settings.local.json";;
    project) printf '%s' "$ROOT/.claude/settings.json";;
    user)    printf '%s' "$HOME/.claude/settings.json";;
    managed) printf '%s' "$MANAGED";;
  esac
}

# ==============
# STATE
#   an absent target copies clean; a populated one is a merge, and saying so beats a lost rule set
# ==============
state_of() {
  local path=$1 rules
  if [ ! -f "$path" ]; then printf 'absent, so the copy lands clean'; return 0; fi
  if ! jq empty "$path" >/dev/null 2>&1; then
    printf 'present but unparseable, so read it before overwriting'; return 0; fi
  rules=$(jq '[.permissions[]?|length]|add // 0' "$path")
  printf 'present with %s rule%s, so merge rather than overwrite' \
    "$rules" "$(if [ "$rules" -eq 1 ]; then echo ''; else echo s; fi)"
}

# ==============
# EMIT
# ==============
MISSING=0
printf '\n=== sandbox.sh sidecar ===\n'
printf 'templates: %s\n' "$TEMPLATES"
printf 'scopes: %s\n' "${WANT[*]}"

for scope in "${WANT[@]}"; do
  template="$TEMPLATES/settings.$scope.json"
  path=$(target_of "$scope")
  printf -- '--- %s ---\n' "$scope"
  if [ ! -f "$template" ]; then
    printf 'template   MISSING at %s\n' "$template"
    MISSING=$((MISSING + 1))
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

# the credential steps are not a copy, so no template carries them and no audit can hand them back
cat <<EOF
--- beyond the copies (masked credentials) ---
keys       mkdir -p ~/.operator && chmod 700 ~/.operator
env        write each token into ~/.operator/.env as: export GH_TOKEN="..."
shell      append to ~/.zshrc: [ -r ~/.operator/.env ] && source ~/.operator/.env
rules      add a mask + injectHosts rule per token to sandbox.credentials.envVars
restart    restart the editor, then start a new claude session
EOF

cat <<'EOF'
--- needs a human (rules no script can judge) ---
- every template is a starting point, since only you know which services you actually reach
- a copy onto a populated scope is a merge; the rules already there were put there for a reason
- run /operator:settings after the copies land, and /operator:credentials once tokens are masked
- the local scope is yours alone, so project rules belong in the project scope instead
========================
EOF

if [ "$MISSING" -gt 0 ]; then exit 1; fi
exit 0

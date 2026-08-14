#!/bin/bash
# =====================================================
# @file setup.sh - install-to-configured setup wizard
# =====================================================
# @description
# PAIR
# - sidecar for `/operator:setup` — probes the machine, then routes the reader to the next step
# - safe anytime: read-only by contract, since every step it names is the user's to run
# - the question it answers is position: what is already in place, and what comes next
# STATE
# - a bare run prints the state block, the route chooser, then the steps still outstanding
# - a step reads `[done]` only when a probe saw it, so nothing is ever claimed on trust
# - every probe degrades to `not observable` rather than failing, since a deny rule is not a fault
# - jq is probed rather than required, because the reader most likely to lack it is the new one
# PREFLIGHT
# - install stays with the reader: a skill cannot install the plugin that carries it
# - it detects which of the three install routes is live, and names the one it found
# RUN
# - `--roadmap` reprints the saved roadmap without probing, which is how a session resumes
# - `--audit` hands the whole turn to `lib/suite.sh`, which prices and gates the run itself
# - `-h` exits before anything runs, and the doc's `## Help` section is what answers it
# - the doc appends one entry to the day's roadmap, never editing an earlier one
# @see plugins/operator/skills/setup/SKILL.md, plugins/operator/lib/suite.sh, .construct/operator/setup/

set -euo pipefail

# the doc is read only after this has already run, so help is refused here or not at all; the doc's
# own '## Help' section owns the output, which is why this prints a marker rather than a usage text
case " $* " in *" --help "*|*" -h "*) echo "help: requested"; exit 0;; esac

# ==============
# PREFLIGHT
# ==============
# resolve from this file before any cd, since BASH_SOURCE arrives relative and cwd holds no
# plugins/operator/ once the plugin is installed from a marketplace
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)
SUITE=$(cd "$HERE/../../lib" 2>/dev/null && pwd || true)/suite.sh

ROADMAP_ONLY=0
AUDIT=0
SUITE_ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --roadmap) ROADMAP_ONLY=1;;
    --audit) AUDIT=1;;
    --confirm) SUITE_ARGS+=("$1");;
    *) echo "fatal: unknown flag $1" >&2; exit 1;;
  esac
  shift
done

# the suite owns its own estimate and its own confirm gate, so the flags pass through untouched:
# gating it here twice would price a run this file cannot measure
if [ "$AUDIT" -eq 1 ]; then
  if [ ! -f "$SUITE" ]; then
    echo "fatal: no lib/suite.sh reachable from this sidecar" >&2; exit 1; fi
  exec bash "$SUITE" ${SUITE_ARGS[@]+"${SUITE_ARGS[@]}"}
fi

# a missing tool is the finding this wizard exists to report, so it is probed and never required
JQ=0; command -v jq >/dev/null 2>&1 && JQ=1
GIT=0; command -v git >/dev/null 2>&1 && GIT=1
CURL=0; command -v curl >/dev/null 2>&1 && CURL=1

# a reader part-way through install has no repo yet, so the roadmap follows cwd until one exists
ROOT=$PWD
if [ "$GIT" -eq 1 ] && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  ROOT=$(git rev-parse --show-toplevel)
  cd "$ROOT"
fi

USER_SCOPE="$HOME/.claude/settings.json"
PROJECT_SCOPE="$ROOT/.claude/settings.json"
LOCAL_SCOPE="$ROOT/.claude/settings.local.json"
MANAGED_SCOPE="/Library/Application Support/ClaudeCode/managed-settings.json"
ROADMAP_DIR=".construct/operator/setup/roadmap"
AUDIT_DIR=".construct/operator/setup/audit"

TODO=0
step() {
  # "[done]" is only ever printed from a probe, so an unreadable scope reads as work instead
  if [ "$1" = "have" ]; then printf '%-2s [done] %-11s %s\n' "$2" "$3" "$4"
  else TODO=$((TODO + 1)); printf '%-2s [todo] %-11s %s\n' "$2" "$3" "$4"; fi
}

# a scope this sidecar cannot read is reported as unreadable: a deny rule working is not a gap
jq_query() {
  local file=$1 filter=$2
  [ "$JQ" -eq 1 ] || return 1
  [ -f "$file" ] || return 1
  jq -e "$filter" "$file" >/dev/null 2>&1
}

# ==============
# STATE - what a probe can see, before any step is named
# ==============
state_deps() {
  local missing=''
  [ "$JQ" -eq 1 ]   || missing="$missing jq"
  [ "$GIT" -eq 1 ]  || missing="$missing git"
  [ "$CURL" -eq 1 ] || missing="$missing curl"
  if [ -n "$missing" ]; then
    printf 'deps       MISSING%s, so step 1 comes before everything below\n' "$missing"
  else
    printf 'deps       bash %s, jq %s, git and curl all present\n' \
      "${BASH_VERSION%%(*}" "$(jq --version 2>/dev/null | sed 's/^jq-//')"
  fi
}

# three install routes leave three different traces, so the trace is what names the route
state_route() {
  local link
  if [ -L "$HOME/.claude/skills/operator" ]; then
    link=$(readlink "$HOME/.claude/skills/operator" 2>/dev/null || echo '?')
    printf 'route      clone, symlinked from %s\n' "$link"
  elif jq_query "$PROJECT_SCOPE" '.extraKnownMarketplaces.TheConstruct'; then
    printf 'route      team, TheConstruct pinned in .claude/settings.json\n'
  elif [ -d "$HOME/.claude/plugins/marketplaces/TheConstruct" ]; then
    printf 'route      individual, marketplace installed under ~/.claude/plugins\n'
  elif [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
    printf 'route      running from %s, with no marketplace trace to name it\n' "$CLAUDE_PLUGIN_ROOT"
  else
    printf 'route      no install trace found, so step 2 is where this starts\n'
  fi
}

state_style() {
  local scope
  for scope in "$PROJECT_SCOPE" "$USER_SCOPE"; do
    if jq_query "$scope" '.outputStyle == "operator"'; then
      printf 'style      operator, set in %s\n' "${scope/#$HOME/~}"
      return
    fi
  done
  printf 'style      operator not set in any readable scope, so /config is still a step\n'
}

# the scope table is the whole reason the tiers differ, so it prints every scope every run
state_scopes() {
  local pair name path count found=0
  for pair in "managed:$MANAGED_SCOPE" "user:$USER_SCOPE" "project:$PROJECT_SCOPE" "local:$LOCAL_SCOPE"; do
    name=${pair%%:*}
    path=${pair#*:}
    if [ ! -f "$path" ]; then continue; fi
    found=$((found + 1))
    if [ "$JQ" -eq 1 ] && jq empty "$path" >/dev/null 2>&1; then
      count=$(jq '[.permissions[]?|length]|add // 0' "$path" 2>/dev/null || echo '?')
      printf 'scope      %-8s %s rules\n' "$name" "$count"
    else
      printf 'scope      %-8s present, unparsed from here\n' "$name"
    fi
  done
  [ "$found" -eq 0 ] && printf 'scope      none of the four scopes carry a file yet\n'
  return 0
}

# a sandbox block with no allowedDomains is the shape that breaks a masked token, so both are read
state_sandbox() {
  local scope domains
  for scope in "$USER_SCOPE" "$PROJECT_SCOPE" "$LOCAL_SCOPE"; do
    if jq_query "$scope" '.sandbox'; then
      domains=$(jq '[.sandbox.network.allowedDomains[]?]|length' "$scope" 2>/dev/null || echo '?')
      printf 'sandbox    configured in %s, %s allowed domain(s)\n' "${scope/#$HOME/~}" "$domains"
      return
    fi
  done
  printf 'sandbox    no sandbox block in any readable scope, so no tier is live yet\n'
}

# the credential detail belongs to /operator:settings --advanced; this reads far enough to route
state_creds() {
  local masked=0
  if [ -d "$HOME/.operator" ]; then
    printf 'keydir     present, mode %s\n' "$(stat -f '%Lp' "$HOME/.operator" 2>/dev/null \
      || stat -c '%a' "$HOME/.operator" 2>/dev/null || echo '?')"
  else
    printf 'keydir     absent, so tier 5 has not started\n'
  fi
  if [ "$JQ" -eq 1 ] && [ -f "$USER_SCOPE" ]; then
    masked=$(jq '[.sandbox.credentials.envVars[]?|select(.mode=="mask")]|length' "$USER_SCOPE" 2>/dev/null || echo 0)
  fi
  printf 'masked     %s credential(s) masked in the user scope\n' "$masked"
  if jq_query "$USER_SCOPE" '.sandbox.credentials.files[]?|select(.path|test("\\.operator/\\.env$"))'; then
    printf 'deny       the env file is denied, so no agent reads it back\n'
  else
    printf 'deny       NO deny rule for ~/.operator/.env, which lands before any token does\n'
  fi
}

state_artifact() {
  local today count
  today="$ROADMAP_DIR/$(date +%Y-%m-%d).md"
  if [ -f "$today" ]; then
    count=$(grep -c '^## Setup Roadmap #' "$today" 2>/dev/null || true)
    printf 'roadmap    %s, %s entry(s)\n' "$today" "${count:-0}"
  else
    printf 'roadmap    none today, so this run writes the first entry\n'
  fi
  if [ -d "$AUDIT_DIR" ]; then
    count=$(find "$AUDIT_DIR" -name '*.md' -type f 2>/dev/null | wc -l | tr -d ' ')
    printf 'audits     %s suite audit file(s) under %s\n' "$count" "$AUDIT_DIR"
  else
    printf 'audits     none yet, so --audit has never proved this machine\n'
  fi
}

# ==============
# ROADMAP - the reprint, which resumes a session without spending a probe
# ==============
if [ "$ROADMAP_ONLY" -eq 1 ]; then
  printf '\n=== setup.sh sidecar (roadmap) ===\n'
  printf 'mode       reprint, so nothing below was probed this run\n'
  LATEST=$(find "$ROADMAP_DIR" -name '*.md' -type f 2>/dev/null | sort | tail -n 1 || true)
  if [ -z "$LATEST" ]; then
    printf 'roadmap    no roadmap written yet; run /operator:setup with no flag first\n'
    printf '========================\n'
    exit 0
  fi
  printf 'roadmap    %s\n' "$LATEST"
  printf -- '--- saved roadmap (verbatim) ---\n'
  cat "$LATEST"
  printf '========================\n'
  exit 0
fi

# ==============
# TELEMETRY
# ==============
printf '\n=== setup.sh sidecar ===\n'
printf 'mode       wizard\n'
printf -- '--- state ---\n'
state_deps
state_route
state_style
state_scopes
state_sandbox
state_creds
state_artifact

cat <<'EOF'
--- route (two answers pick one tier) ---
q1 who is this sandbox for: only me / this repo / my team / this whole machine
q2 does this machine hold real credentials an agent could read: yes / no
   only me + no     -> tier 1, then tier 3      (--local, then --user)
   this repo + no   -> tier 2                   (--project)
   my team + no     -> tier 2, committed        (--project)
   this machine     -> tier 4                   (--managed, needs sudo)
   any + yes        -> the tier above, then 5   (--advanced)
EOF

printf -- '--- steps, in this order (each one is yours to run) ---\n'
if [ "$JQ" -eq 1 ] && [ "$GIT" -eq 1 ] && [ "$CURL" -eq 1 ]; then
  step have 1 deps 'jq, git and curl are all on PATH'
else
  step need 1 deps 'install the missing tools above; jq gates every probe below'
fi
if [ -L "$HOME/.claude/skills/operator" ] || [ -d "$HOME/.claude/plugins/marketplaces/TheConstruct" ] \
  || jq_query "$PROJECT_SCOPE" '.extraKnownMarketplaces.TheConstruct'; then
  step have 2 install 'a route was detected above; the readme holds all three'
else
  step need 2 install 'pick option A, B or C in the readme; a skill cannot install its own plugin'
fi
if jq_query "$PROJECT_SCOPE" '.outputStyle == "operator"' || jq_query "$USER_SCOPE" '.outputStyle == "operator"'; then
  step have 3 style 'the operator output style is set'
else
  step need 3 style '/config > Output style > operator'
fi
if [ -f "$LOCAL_SCOPE" ] || [ -f "$PROJECT_SCOPE" ] || [ -f "$USER_SCOPE" ]; then
  step have 4 scope 'at least one settings scope carries a file'
else
  step need 4 scope 'run /operator:settings with the flag your q1 answer picked'
fi
if jq_query "$USER_SCOPE" '.sandbox' || jq_query "$PROJECT_SCOPE" '.sandbox' || jq_query "$LOCAL_SCOPE" '.sandbox'; then
  step have 5 sandbox 'a sandbox block is live; /sandbox prints what the session sees'
else
  step need 5 sandbox 'paste the emitted block, restart the editor, then check /sandbox'
fi
if [ -d "$HOME/.operator" ]; then
  step have 6 credentials 'the key directory exists; /operator:settings --advanced walks the rest'
else
  step need 6 credentials 'tier 5 only: /operator:settings --advanced, one step at a time'
fi
if [ -d "$AUDIT_DIR" ]; then
  step have 7 prove 'a suite audit has run; rerun /operator:setup --audit after any change'
else
  step need 7 prove '/operator:setup --audit --confirm, which spends minutes and grades every lens'
fi

cat <<'EOF'
--- needs a human (rules no script can judge) ---
- only you know who this machine is for, so only you can answer q1 and pick the tier
- a step reading [done] was seen by a probe, and a deny rule can hide a step that is finished
- the managed scope lands outside the project and needs sudo, so it is always your call
- restart the editor between a paste and a check, since the session reads settings once at start
- step 7 costs minutes and is the only step here that proves the others worked
========================
EOF

# the doc numbers its entry from this count, so an absent file has to read as zero rather than blank
TODAYS_ROADMAP="$ROADMAP_DIR/$(date +%Y-%m-%d).md"
if [ -f "$ROOT/$TODAYS_ROADMAP" ];
then ROADMAP_COUNT=$(grep -c '^## Setup Roadmap #' "$ROOT/$TODAYS_ROADMAP" || true)
else ROADMAP_COUNT=0; fi
ROADMAP_COUNT=${ROADMAP_COUNT:-0}

printf 'roadmap_file: %s\n' "$TODAYS_ROADMAP"
printf 'roadmap_count: %s\n' "$ROADMAP_COUNT"
printf 'next_roadmap: %s\n' "$((ROADMAP_COUNT + 1))"
printf 'timestamp: %s\n' "$(date '+%Y-%m-%d %H:%M')"
printf 'todo: %s\n' "$TODO"
exit 0

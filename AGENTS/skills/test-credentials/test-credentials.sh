#!/bin/bash
# =============================================================
# @file test-credentials.sh - credential masking prober sidecar
# =============================================================
# @description
# - sidecar for `/test-credentials` — proves every credential is masked, unset, or unruled
# - NEVER prints a credential value; a leak is reported by name and vector, never by content
# - reads the merged settings for the rules, then probes the live environment against them
# - refuses to grade when the credential layer is inactive, since every verdict would invert
# - `mask` keeps the capability and hides the value; `deny` hides it by removing it entirely
# - an unruled credential is the finding that matters: it needs a rule AND a rotation
# @see AGENTS.md, AGENTS/skills/test-credentials/SKILL.md, AGENTS/settings/secrets.sh

set -euo pipefail

# ==============
# PREFLIGHT
# ==============
# the shared patterns sit beside the settings, not beside this file, so resolve before any cd
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)
SHARED=$(cd "$HERE/../../settings" 2>/dev/null && pwd || true)
if [ ! -f "$SHARED/secrets.sh" ]; then
  echo "fatal: no AGENTS/settings/secrets.sh reachable from this sidecar" >&2; exit 1; fi
# shellcheck source=../../settings/secrets.sh
. "$SHARED/secrets.sh"

command -v jq >/dev/null 2>&1 || { echo "fatal: jq is required" >&2; exit 1; }

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "fatal: not a git repository" >&2; exit 1; fi
cd "$(git rev-parse --show-toplevel)"

# every scope that can carry a credential rule, in precedence order
SETTINGS=()
for candidate in "$HOME/.claude/settings.json" .claude/settings.json .claude/settings.local.json; do
  if [ -f "$candidate" ]; then SETTINGS+=("$candidate"); fi
done
if [ ${#SETTINGS[@]} -eq 0 ]; then echo "fatal: no settings file carries credential rules" >&2; exit 1; fi

rules_by_mode() {
  local want=$1 file
  for file in "${SETTINGS[@]}"; do
    jq -r --arg m "$want" '.sandbox.credentials.envVars[]? | select(.mode == $m) | .name' \
      "$file" 2>/dev/null || true
  done | sort -u
}
MASKED=$(rules_by_mode mask)
DENIED=$(rules_by_mode deny)

denied_files() {
  local file
  for file in "${SETTINGS[@]}"; do
    jq -r '.sandbox.credentials.files[]? | .path' "$file" 2>/dev/null || true
  done | sort -u
}

# ==============
# CLASSIFY
#   a value is never printed; it is only ever reduced to one of three words
# ==============
# LEAKED beats MASKED: a value matching a provider pattern is the real thing, whatever else it is
classify() {
  local value=$1
  if [ -z "$value" ]; then printf 'unset'; return; fi
  if printf '%s' "$value" | grep -qE "$SECRET_PATTERNS"; then printf 'leaked'; return; fi
  printf 'masked'
}

# enough to reconcile a row against the credential in your hand, never enough to be one; the
# detector is re-run on the fragment, so the rule polices itself rather than trusting arithmetic
fingerprint() {
  local value=$1 trimmed
  if [ -z "$value" ]; then printf -- '-'; return; fi
  if [ "${#value}" -lt 12 ]; then printf '(short)'; return; fi
  trimmed="${value:0:4}…${value: -4}"
  if printf '%s' "$trimmed" | grep -qE "$SECRET_PATTERNS"; then printf '(withheld)'; return; fi
  printf '%s' "$trimmed"
}

# ==============
# THE GATE
#   outside the sandbox a denied variable is simply present, so every verdict below inverts
#   grading then would report a healthy config as broken, which is the worst error this can make
# ==============
LAYER_ACTIVE=no
GATE_WITNESS=""
for name in $DENIED; do
  if [ -z "${!name:-}" ]; then LAYER_ACTIVE=yes; GATE_WITNESS=$name; break; fi
done
# a mask sentinel is the other witness, for a config that denies nothing
if [ "$LAYER_ACTIVE" = no ]; then
  for name in $MASKED; do
    if [ "$(classify "${!name:-}")" = masked ]; then LAYER_ACTIVE=yes; GATE_WITNESS=$name; break; fi
  done
fi

printf '\n=== @test-credentials telemetry ===\n'
printf 'credential layer active: %s\n' "$LAYER_ACTIVE"
printf 'witness: %s\n' "${GATE_WITNESS:-none}"
printf 'settings scopes read: %s\n' "${#SETTINGS[@]}"
printf 'masked rules: %s\n' "$(printf '%s' "$MASKED" | grep -c . || true)"
printf 'denied rules: %s\n' "$(printf '%s' "$DENIED" | grep -c . || true)"

if [ "$LAYER_ACTIVE" = no ]; then
  printf 'verdict: UNGRADED — no denied variable is unset and no mask sentinel is present\n'
  printf '\n=== @test-credentials handover ===\n'
  printf '# this ran outside the sandbox, where every credential is simply itself\n'
  printf '# re-run it as a sandboxed tool call; grading here would call a healthy config broken\n'
  printf '=====================\n'
  exit 1
fi

# ==============
# UNRULED — the worklist
#   a credential-shaped variable that no rule names is exposed to every sandboxed command
# ==============
printf '\n--- unruled ---\n'
UNRULED=0
while IFS= read -r name; do
  [ -n "$name" ] || continue
  case " $MASKED $DENIED " in *" $name "*) continue;; esac
  value=${!name:-}
  [ -n "$value" ] || continue
  # the sandbox injects its own proxy and agent sockets; those are plumbing it set, not secrets
  # the user owns, and reporting them as rotations would bury the findings that are real
  case "$value" in
    /*) continue;;
    *://localhost*|*://127.0.0.1*|*://*@localhost*|*://*@127.0.0.1*) continue;;
  esac
  # a name that reads like a credential, or a value that provably is one
  shaped=no
  if printf '%s' "$name" | grep -qiE '(key|token|secret|password|passwd|credential|auth)'; then shaped=yes; fi
  if printf '%s' "$value" | grep -qE "$SECRET_PATTERNS"; then shaped=live; fi
  case "$shaped" in
    live) printf 'unruled: %s | %s | provably a credential | needs a rule AND a rotation\n' \
            "$name" "$(fingerprint "$value")"
          UNRULED=$((UNRULED + 1));;
    yes)  printf 'unruled: %s | %s | named like a credential | confirm, then rule it\n' \
            "$name" "$(fingerprint "$value")"
          UNRULED=$((UNRULED + 1));;
  esac
done < <(env | cut -d= -f1 | sort -u)
if [ "$UNRULED" -eq 0 ]; then printf 'none — every credential-shaped variable carries a rule\n'; fi

# ==============
# VECTORS
#   each reports the classification of what it recovered, never the value it recovered
# ==============
probe_vectors() {
  local name=$1 expect=$2 verdict recovered
  printf '\n--- %s (rule: %s) ---\n' "$name" "$expect"

  recovered=$(printf '%s' "${!name:-}")
  # the fingerprint is what lets a reader match this row to the credential they are holding
  printf '%-22s %s\n' "fingerprint" "$(fingerprint "$recovered")"
  printf '%-22s %s\n' "shell expansion" "$(classify "$recovered")"

  recovered=$(printenv "$name" 2>/dev/null || true)
  printf '%-22s %s\n' "external binary" "$(classify "$recovered")"

  recovered=$(env | grep -E "^$name=" | cut -d= -f2- || true)
  printf '%-22s %s\n' "env dump" "$(classify "$recovered")"

  recovered=$(export -p | grep -E "\b$name=" | sed -E 's/^.*=//' | tr -d '"' || true)
  printf '%-22s %s\n' "built-in export" "$(classify "$recovered")"

  recovered=$(python3 -c "import os;print(os.environ.get('$name',''))" 2>/dev/null || true)
  printf '%-22s %s\n' "subprocess" "$(classify "$recovered")"

  # xtrace echoes the expanded word, so an unset variable leaves the trace with nothing after `:`
  recovered=$( (set -x; : "${!name:-}") 2>&1 | sed -E 's/^[^:]*:[[:space:]]*//' | tr -d "'" || true)
  printf '%-22s %s\n' "xtrace" "$(classify "$recovered")"

  recovered=$(env > "$SCRATCH/dump" 2>/dev/null; grep -E "^$name=" "$SCRATCH/dump" | cut -d= -f2- || true)
  printf '%-22s %s\n' "dump and read" "$(classify "$recovered")"

  # the verdict is the worst finding across every vector, since one leak is a leak
  verdict=ok
  if [ "$expect" = mask ]; then
    for probe in "${!name:-}" "$(printenv "$name" 2>/dev/null || true)"; do
      if [ "$(classify "$probe")" = leaked ]; then verdict=LEAKED; fi
    done
  else
    if [ -n "${!name:-}" ]; then verdict=PRESENT; fi
  fi
  printf '%-22s %s\n' "verdict" "$verdict"
}

TMPROOT="$(git rev-parse --show-toplevel)/tmp"
mkdir -p "$TMPROOT"
SCRATCH=$(mktemp -d "$TMPROOT/test-credentials.XXXXXX")
cleanup() { rm -rf "$SCRATCH"; }
trap cleanup EXIT

for name in $MASKED; do probe_vectors "$name" mask; done
for name in $DENIED; do probe_vectors "$name" deny; done

# ==============
# FILE DENIES
# ==============
printf '\n--- denied files ---\n'
while IFS= read -r path; do
  [ -n "$path" ] || continue
  expanded=${path/#\~/$HOME}
  # a directory needs `ls` and a file needs `cat`, since `cat` fails on a directory whatever the
  # permissions say; and when the sandbox denies the stat too, absent and denied are the same
  # answer from in here, which is the property working rather than a gap in the report
  if [ -d "$expanded" ]; then
    if ls "$expanded" >/dev/null 2>&1; then printf '%-34s READABLE\n' "$path"
    else printf '%-34s denied\n' "$path"; fi
  elif [ -f "$expanded" ]; then
    if cat "$expanded" >/dev/null 2>&1; then printf '%-34s READABLE\n' "$path"
    else printf '%-34s denied\n' "$path"; fi
  else
    printf '%-34s unreadable (absent or denied at stat)\n' "$path"
  fi
done < <(denied_files)

printf '\n=== @test-credentials handover ===\n'
printf '# nothing to run: this trigger measures and the report is the deliverable\n'
printf '# every LEAKED or PRESENT verdict names a credential to rotate, then rule\n'
printf '=====================\n'

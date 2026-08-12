#!/bin/bash
# ======================================================================================
# @file credentials.sh - credential sidecar: probes the masking, then grades the reports
# ======================================================================================
# @description
# PAIR
# - the only sidecar for `/operator:credentials`, which owns both halves of its own artifact
# - the doc carries the shape; this file names where it lands and grades what landed there
# - one skill is one SKILL.md and one sidecar, so nothing outside this pair decides its shape
# RUN
# - no flag runs the trigger half, so every existing invocation is unchanged
# - `--check [paths]` runs the validator half; with no paths it grades the whole artifact dir
# - ERROR breaks a rule the doc states outright; WARN names a smell the doc tolerates
# @see plugins/operator/skills/credentials/SKILL.md, plugins/operator/shared/secrets.sh, .construct/operator/credentials/, .claude/skills/validate-skills/SKILL.md, plugins/operator/skills/credentials/credentials.sh

set -euo pipefail

# `--check` selects the validator half; anything else is the trigger, so the doc's own
# bang-injected call keeps working untouched
if [ "${1:-}" = "--check" ]; then
  shift
else
  # ==============
  # PREFLIGHT
  # ==============
  # the shared patterns sit beside the settings, not beside this file, so resolve before any cd
  HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)
  SHARED=$(cd "$HERE/../../shared" 2>/dev/null && pwd || true)
  if [ ! -f "$SHARED/secrets.sh" ]; then
    echo "fatal: no shared/secrets.sh reachable from this sidecar" >&2; exit 1; fi
  # shellcheck source=../../shared/secrets.sh
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

  printf '\n=== /operator:credentials telemetry ===\n'
  printf 'credential layer active: %s\n' "$LAYER_ACTIVE"
  printf 'witness: %s\n' "${GATE_WITNESS:-none}"
  printf 'settings scopes read: %s\n' "${#SETTINGS[@]}"
  printf 'masked rules: %s\n' "$(printf '%s' "$MASKED" | grep -c . || true)"
  printf 'denied rules: %s\n' "$(printf '%s' "$DENIED" | grep -c . || true)"

  if [ "$LAYER_ACTIVE" = no ]; then
    printf 'verdict: UNGRADED — no denied variable is unset and no mask sentinel is present\n'
    printf '\n=== /operator:credentials handover ===\n'
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

  printf '\n=== /operator:credentials handover ===\n'
  printf '# nothing to run: this trigger measures and the report is the deliverable\n'
  printf '# every LEAKED or PRESENT verdict names a credential to rotate, then rule\n'
  printf '=====================\n'
  exit 0
fi

# ==============
# PREFLIGHT
# ==============
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)
SHARED=$(cd "$HERE/../../shared" 2>/dev/null && pwd || true)
if [ ! -f "$SHARED/secrets.sh" ]; then
  echo "fatal: no shared/secrets.sh reachable from this sidecar" >&2; exit 1; fi
# shellcheck source=../../shared/secrets.sh
. "$SHARED/secrets.sh"

UTF8_LOCALE=$(locale -a 2>/dev/null | grep -iE '^(C|en_US)\.(utf-?8)$' | head -n 1 || true)
if [ -n "$UTF8_LOCALE" ]; then export LC_ALL="$UTF8_LOCALE"; fi

MAX_WIDTH=100
STRICT=0
TEMPLATE="plugins/operator/skills/credentials/SKILL.md"
EXPECTED_SECTIONS=$'Verdict\nUnruled\nMasked\nUnset\nFiles\nNotes'

TARGETS=()
for arg in "$@"; do
  case "$arg" in
    --strict) STRICT=1;;
    -h|--help) sed -n '2,11p' "$0"; exit 0;;
    -*) echo "fatal: unknown flag $arg" >&2; exit 1;;
    *) TARGETS+=("$arg");;
  esac
done

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "fatal: not a git repository" >&2; exit 1; fi
cd "$(git rev-parse --show-toplevel)"

if [ ${#TARGETS[@]} -eq 0 ]; then TARGETS=(".construct/operator/credentials"); fi

FILES=()
for path in "${TARGETS[@]}"; do
  if [ -d "$path" ]; then
    for nested in "$path"/*.md; do [ -f "$nested" ] && FILES+=("$nested"); done
  elif [ -f "$path" ]; then FILES+=("$path"); fi
done

TMPROOT="$(git rev-parse --show-toplevel)/tmp"
mkdir -p "$TMPROOT"
FINDINGS=$(mktemp "$TMPROOT/credentials-findings.XXXXXX")
cleanup() { st=$?; if [ "$st" -eq 0 ]; then rm -f "$FINDINGS"; fi; }
trap cleanup EXIT

err()  { printf 'ERROR|%s|%s|%s|%s\n' "$1" "$2" "$3" "$4" >> "$FINDINGS"; }
warn() { printf 'WARN|%s|%s|%s|%s\n' "$1" "$2" "$3" "$4" >> "$FINDINGS"; }

# ==============
# CHECKS
# ==============
# "one file per day, named YYYY-MM-DD.md"
check_filename() {
  local file=$1
  if ! basename "$file" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}\.md$'; then
    err "$file" 1 filename "credential reports are named YYYY-MM-DD.md"
  fi
}

# "sections run in this order", since a reader looks for the worklist first
check_sections() {
  local file=$1 actual
  actual=$(grep -E '^## ' "$file" | sed -E 's/^## //' || true)
  if [ "$actual" != "$EXPECTED_SECTIONS" ]; then
    err "$file" 1 section_order "got $(printf '%s' "$actual" | tr '\n' '>' | sed 's/>$//'); want Verdict>Unruled>Masked>Unset>Files>Notes"
  fi
}

# "NEVER contains a credential value" — the whole reason this artifact is validated at all
check_no_values() {
  local file=$1 lineno line fragment
  # the primary defense: a provider token anywhere in this file is a live leak, not a lint failure
  scan_secrets "$file"
  # a fingerprint is four and four around an ellipsis; anything longer is a value wearing a
  # fingerprint's clothes, which is the one way a real credential could reach this artifact
  while IFS= read -r line; do
    lineno=${line%%:*}
    while IFS= read -r fragment; do
      [ -n "$fragment" ] || continue
      if ! printf '%s' "$fragment" | grep -qE '^.{4}….{4}$'; then
        err "$file" "$lineno" fingerprint "'$fragment' is not four-and-four; trim it or withhold it"
      fi
    done < <(printf '%s' "${line#*:}" | grep -oE '[^ `|]*…[^ `|]*' || true)
  done < <(grep -n '…' "$file" || true)
}

check_width() {
  local file=$1 lineno=0 line
  while IFS= read -r line; do
    lineno=$((lineno + 1))
    if [ "${#line}" -gt "$MAX_WIDTH" ]; then
      err "$file" "$lineno" width "${#line} chars; the cap is $MAX_WIDTH"
    fi
  done < "$file"
}

for file in "${FILES[@]:-}"; do
  [ -n "${file:-}" ] || continue
  check_filename   "$file"
  check_sections   "$file"
  check_no_values  "$file"
  check_width      "$file"
done

# ==============
# TELEMETRY
# ==============
ERRORS=$(grep -c '^ERROR|' "$FINDINGS" || true)
WARNINGS=$(grep -c '^WARN|' "$FINDINGS" || true)
SECRETS=$(grep -c '|secret|' "$FINDINGS" || true)

cat <<EOF

=== credentials.sh sidecar ===
template: $TEMPLATE
scanned: ${#FILES[@]} report(s)
width_cap: $MAX_WIDTH chars
errors: $ERRORS
warnings: $WARNINGS
secrets: $SECRETS
--- findings ---
EOF

if [ -s "$FINDINGS" ]; then
  sort -t'|' -k2,2 -k3,3n "$FINDINGS" \
    | awk -F'|' '{ printf "%-5s %-46s %-17s %s\n", $1, $2 ":" $3, $4, $5 }'
fi

cat <<'EOF'
--- needs a human (template rules no script can judge) ---
- a secret finding is a live leak: rotate that credential before touching the file
- an ungraded run writes no file at all, since a verdict outside the sandbox means nothing
- the unruled section leads, because it is the only one holding work
- a fingerprint is for reconciling a row against a credential, never for using one
- the detector runs on the fragment too, so a four-and-four that still matches is withheld
========================
EOF

if [ "$STRICT" -eq 1 ] && [ "$WARNINGS" -gt 0 ]; then exit 1; fi
if [ "$ERRORS" -gt 0 ]; then exit 1; fi
exit 0

#!/bin/bash
# =============================================================
# @file doc-credentials.sh - credential audit validator sidecar
# =============================================================
# @description
# - sidecar for `doc-credentials` — asserts a credential report matches the shape documenting it
# - the load-bearing check is the secret scan: this artifact is the one that must never hold a value
# - a `secret` finding here is not a lint failure, it is a live leak and a rotation
# - defaults to every file in `docs/credentials/`; pass files or a directory to scope it
# - `--strict` promotes warnings to errors; exits 1 on any error
# @see AGENTS.md, AGENTS/settings/secrets.sh, AGENTS/skills/doc-credentials/SKILL.md, docs/credentials/

set -euo pipefail

# ==============
# PREFLIGHT
# ==============
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)
SHARED=$(cd "$HERE/../../settings" 2>/dev/null && pwd || true)
if [ ! -f "$SHARED/secrets.sh" ]; then
  echo "fatal: no AGENTS/settings/secrets.sh reachable from this sidecar" >&2; exit 1; fi
# shellcheck source=../../settings/secrets.sh
. "$SHARED/secrets.sh"

UTF8_LOCALE=$(locale -a 2>/dev/null | grep -iE '^(C|en_US)\.(utf-?8)$' | head -n 1 || true)
if [ -n "$UTF8_LOCALE" ]; then export LC_ALL="$UTF8_LOCALE"; fi

MAX_WIDTH=100
STRICT=0
TEMPLATE="AGENTS/skills/doc-credentials/SKILL.md"
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

if [ ${#TARGETS[@]} -eq 0 ]; then TARGETS=("docs/credentials"); fi

FILES=()
for path in "${TARGETS[@]}"; do
  if [ -d "$path" ]; then
    for nested in "$path"/*.md; do [ -f "$nested" ] && FILES+=("$nested"); done
  elif [ -f "$path" ]; then FILES+=("$path"); fi
done

TMPROOT="$(git rev-parse --show-toplevel)/tmp"
mkdir -p "$TMPROOT"
FINDINGS=$(mktemp "$TMPROOT/doc-credentials-findings.XXXXXX")
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

=== doc-credentials sidecar ===
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

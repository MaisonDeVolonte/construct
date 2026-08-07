#!/bin/bash
# =============================================================
# @file sync-secrets.sh - holds every secrets.sh copy identical
# =============================================================
# @description
# PAIR
# - sidecar for `sync-secrets` — keeps the per-plugin `secrets.sh` copies byte-identical
# - a plugin install copies one plugin directory and never a sibling, so the file cannot be shared
# - `/gitgud:audit` reports that drift and stays read-only; this tool is the half that repairs it
# SHAPE
# - operator carries the canonical copy, since it is the bundle every install pulls
# - a copy is identical or replaced whole; there is no merge, no region and no three-way
# - siblings are discovered rather than listed, so a new plugin is covered without an edit here
# RUN
# - `--check` is the default and the only mode ci runs; it exits 1 on any drift
# - `--write` overwrites every stale copy from the canonical, and never edits the canonical
# @see tools/check-skills/check-skills.sh, plugins/operator/shared/secrets.sh, .github/workflows/ci.yml

set -euo pipefail

# ==============
# PREFLIGHT
# ==============
MODE="check"

for arg in "$@"; do
  case "$arg" in
    --check) MODE="check";;
    --write) MODE="write";;
    -h|--help) sed -n '2,18p' "$0"; exit 0;;
    *) echo "fatal: unknown flag $arg" >&2; exit 1;;
  esac
done

# every path below is repo-relative, since the canonical is named by its position in the tree
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "fatal: not a git repository" >&2; exit 1; fi
cd "$(git rev-parse --show-toplevel)"

CANONICAL="plugins/operator/shared/secrets.sh"
if [ ! -f "$CANONICAL" ]; then
  echo "fatal: no $CANONICAL to sync from" >&2; exit 1; fi

COPIES=()
for candidate in plugins/*/shared/secrets.sh; do
  [ -f "$candidate" ] || continue
  [ "$candidate" = "$CANONICAL" ] && continue
  COPIES+=("$candidate")
done
# set -u makes an empty array expansion fatal, which would read as a crash rather than a clean scan
if [ ${#COPIES[@]} -eq 0 ]; then
  echo "fatal: no sibling secrets.sh found beside $CANONICAL" >&2; exit 1; fi

# ==============
# SYNC
# ==============
DRIFTED=0
SYNCED=0
FINDINGS=""

for copy in "${COPIES[@]}"; do
  if cmp -s "$CANONICAL" "$copy"; then continue; fi
  DRIFTED=$((DRIFTED + 1))
  if [ "$MODE" = write ]; then
    cp "$CANONICAL" "$copy"
    SYNCED=$((SYNCED + 1))
    FINDINGS="${FINDINGS}SYNCED $copy"$'\n'
  else
    FINDINGS="${FINDINGS}DRIFT  $copy"$'\n'
  fi
done

# ==============
# TELEMETRY
# ==============
cat <<EOF

=== sync-secrets telemetry ===
canonical: $CANONICAL
copies: ${#COPIES[@]}
mode: $MODE
drifted: $DRIFTED
synced: $SYNCED
--- findings ---
EOF

if [ "$DRIFTED" -eq 0 ]; then
  echo "none — every copy matches the canonical"
else
  printf '%s' "$FINDINGS"
fi

# the repair is one command, so it is emitted rather than described; check never mutates
if [ "$MODE" = check ] && [ "$DRIFTED" -gt 0 ]; then
  cat <<'EOF'
--- handover ---
# overwrite every stale copy from the canonical, then re-run the check
tools/sync-secrets/sync-secrets.sh --write
EOF
fi
echo "=============================="

if [ "$MODE" = check ] && [ "$DRIFTED" -gt 0 ]; then exit 1; fi
exit 0

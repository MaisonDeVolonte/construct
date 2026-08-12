#!/bin/bash
# ================================================
# @file backup.sh - full repo snapshot and restore
# ================================================
# @description
# PAIR
# - sidecar for `/gitgud:backup` — takes and verifies the snapshot, then hands the restore over
# - run only on the explicit command, and worth typing before any destructive work
# - the one trigger that needs no confirmation, since a copy destroys nothing it finds
# SNAPSHOT
# - the only sidecar that mutates on its own, since a copy adds safety and spends none
# - history and working tree are captured separately: a `.git` copy alone loses uncommitted work
# - the tree copy is tracked plus untracked-not-ignored, the exact set `clean -fd` can destroy
# - ignored files are skipped on purpose, the same reason `/gitgud:nuke` stashes with -u not -a
# - the destination is fixed at gitignored `tmp/backups/`, so it never becomes a copy-anywhere tool
# HANDOVER
# - the restore is handed over, never run: putting files back overwrites what sits there now
# - `cp` here is invisible to the deny list and the hook, since script lines are not tool calls
# - that gap is the design: a reviewed sidecar holds a capability the loose agent never gets
# @see plugins/gitgud/skills/backup/SKILL.md, plugins/gitgud/skills/nuke/SKILL.md, plugins/gitgud/shared/handover.sh, .claude/skills/validate-skills/SKILL.md

set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)
SHARED=$(cd "$HERE/../../shared" 2>/dev/null && pwd || true)
if [ ! -f "$SHARED/handover.sh" ]; then
  echo "fatal: no plugins/gitgud/shared/handover.sh reachable from this sidecar" >&2; exit 1; fi
# shellcheck source=../../shared/handover.sh
. "$SHARED/handover.sh"

if [ "$#" -gt 0 ]; then
  echo "fatal: git-backup takes no arguments; the destination is fixed at tmp/backups/" >&2
  exit 1
fi

require_repo
require_tools cp find

# every path is relative to the repo root, so a run from a subdirectory still lands in one place
ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"

STAMP=$(date +%Y-%m-%d-%H%M%S)
DEST="tmp/backups/$STAMP"

if [ -e "$DEST" ]; then
  echo "fatal: $DEST already exists, refusing to overwrite a backup" >&2; exit 1; fi

CURRENT_BRANCH=$(git_current_branch)
HEAD_SHA=$(git rev-parse HEAD 2>/dev/null || echo "none")
TRACKED_COUNT=$(git ls-files | grep -c . || true)
UNTRACKED_COUNT=$(git ls-files --others --exclude-standard | grep -c . || true)
MODIFIED_COUNT=$(git status --porcelain=v1 | grep -cE '^[ MADRCU]' || true)
BRANCH_COUNT=$(git for-each-ref --format='%(refname:short)' refs/heads/ | grep -c . || true)
STASH_COUNT=$(git stash list | grep -c . || true)

mkdir -p "$DEST/worktree"

# ==============
# HISTORY
# ==============
# named `git` rather than `.git` so it is visible in a listing and clone-able as a path
cp -R .git "$DEST/git"

SOURCE_OBJECTS=$(find .git/objects -type f | grep -c . || true)
BACKUP_OBJECTS=$(find "$DEST/git/objects" -type f | grep -c . || true)

if [ "$SOURCE_OBJECTS" != "$BACKUP_OBJECTS" ]; then
  echo "fatal: object count mismatch, $SOURCE_OBJECTS in .git vs $BACKUP_OBJECTS in backup" >&2
  echo "the backup at $DEST is incomplete; delete it and retry" >&2
  exit 1
fi

# ==============
# WORKING TREE
# ==============
# tracked plus untracked-not-ignored is exactly what `clean -fd` and `reset --hard` can destroy
# copying ignored files too would sweep `.env` in for nothing, since neither command reaches it
COPIED=0
while IFS= read -r -d '' file; do
  [ -f "$file" ] || continue
  mkdir -p "$DEST/worktree/$(dirname "$file")"
  cp -p "$file" "$DEST/worktree/$file"
  COPIED=$((COPIED + 1))
done < <(
  { git ls-files -z; git ls-files --others --exclude-standard -z; } | sort -zu
)

BACKUP_SIZE=$(du -sh "$DEST" | awk '{print $1}')
BACKUP_TOTAL=$(du -sh tmp/backups 2>/dev/null | awk '{print $1}')
BACKUP_COUNT=$(find tmp/backups -mindepth 1 -maxdepth 1 -type d | grep -c . || true)

# ==============
# MANIFEST
# ==============
# written into the backup so it explains itself months later, without this sidecar to read it
{
  printf 'git-backup %s\n' "$STAMP"
  printf 'head: %s\n' "$HEAD_SHA"
  printf 'branch: %s\n' "${CURRENT_BRANCH:-detached}"
  printf 'tracked files: %s\n' "$TRACKED_COUNT"
  printf 'untracked files: %s\n' "$UNTRACKED_COUNT"
  printf 'local branches: %s\n' "$BRANCH_COUNT"
  printf 'stash entries: %s\n' "$STASH_COUNT"
  printf 'git objects: %s\n' "$BACKUP_OBJECTS"
  printf '\nignored files are NOT in this snapshot, by design\n'
  printf '\nrestore history:  git clone %s/git <somewhere>\n' "$DEST"
  printf 'restore one file: cp %s/worktree/<path> <path>\n' "$DEST"
} > "$DEST/MANIFEST.txt"

telemetry_open gitgud:backup
telemetry_line "backup location" "$DEST"
telemetry_line "head" "$HEAD_SHA"
telemetry_line "branch" "${CURRENT_BRANCH:-detached}"
telemetry_line "git objects copied" "$BACKUP_OBJECTS"
telemetry_line "working files copied" "$COPIED"
telemetry_line "modifications captured" "$MODIFIED_COUNT"
telemetry_line "untracked captured" "$UNTRACKED_COUNT"
telemetry_line "local branches" "$BRANCH_COUNT"
telemetry_line "stash entries" "$STASH_COUNT"
telemetry_line "snapshot size" "$BACKUP_SIZE"
telemetry_line "backups on disk" "${BACKUP_COUNT:-0} totalling ${BACKUP_TOTAL:-0}"
telemetry_line "verified" "object counts match at $SOURCE_OBJECTS"

# the restore is handed over rather than run: putting files back overwrites whatever sits there
# now, which is the one thing a backup tool must never decide on the user's behalf
handover_open gitgud:backup
handover_note "the snapshot is already taken; nothing below runs unless you paste it"
handover_note "restore the full history into a fresh directory, then look before you swap:"
handover_cmd "git clone $DEST/git restored-$STAMP"
handover_note "or put a single working file back exactly where it was:"
handover_cmd "cp $DEST/worktree/<path> <path>"
handover_note "read $DEST/MANIFEST.txt for what this snapshot holds"
if [ "${BACKUP_COUNT:-0}" -gt 5 ]; then
  handover_note "$BACKUP_COUNT snapshots now hold $BACKUP_TOTAL; delete the stale ones yourself:"
  handover_cmd "rm -rf tmp/backups/<stamp>"
fi
block_close

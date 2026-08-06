#!/bin/bash
# ==================================================
# @file handover.sh - shared git sidecar scaffolding
# ==================================================
# @description
# - sourced by every `AGENTS/skills/*/*.sh`, so the whole family shares one output shape
# - every git call here is on the permissions allow list; nothing in it mutates a repo
# - `git_default_branch` asks the remote directly, since symbolic-ref and set-head are denied
# - the handover block is the deliverable: measured here, pasted and run by the user
# - the trigger block is the narrow exception: measured here, run by the trigger as a tool call
# - a sidecar that needs to mutate emits the command instead of running it, into either block
# @see AGENTS.md, AGENTS/templates/git.md, AGENTS/settings/settings.user.md, AGENTS/skills/

# ==============
# PREFLIGHT
# ==============
require_repo() {
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "fatal: not a git repository" >&2; exit 1; fi
}

# a half-finished merge makes every measurement below describe a tree nobody asked for
require_no_op_in_progress() {
  if [ -d ".git/rebase-merge" ] || [ -d ".git/rebase-apply" ] \
    || [ -f ".git/MERGE_HEAD" ] || [ -f ".git/CHERRY_PICK_HEAD" ]; then
    echo "fatal: merge, rebase, or cherry-pick in progress" >&2; exit 1; fi
}

require_tools() {
  local tool
  for tool in "$@"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      echo "fatal: $tool is required" >&2; exit 1; fi
  done
}

# ==============
# QUERIES
# ==============
# ls-remote reads the remote's own HEAD, so it needs no local origin/HEAD to have been set;
# that matters because `git remote set-head` and `git symbolic-ref` are both denied now
git_default_branch() {
  local name
  name=$(git ls-remote --symref origin HEAD 2>/dev/null \
    | awk '/^ref:/ { sub("refs/heads/", "", $2); print $2; exit }')
  # offline fallback: whatever a previous fetch already recorded locally
  if [ -z "$name" ]; then
    name=$(git rev-parse --abbrev-ref origin/HEAD 2>/dev/null | sed 's@^origin/@@' || true)
  fi
  printf '%s' "$name"
}

# empty on a detached HEAD, which every caller treats as fatal
git_current_branch() {
  git branch --show-current 2>/dev/null || printf ''
}

git_is_dirty() {
  [ -n "$(git status --porcelain 2>/dev/null)" ]
}

# absorbed: would merging $2 into $1 change anything? trees, not patch-ids, so a rebase survives it
# a conflict, or a git too old for --write-tree, reports no — the fail-safe answer is "keep it"
is_absorbed() {
  local merged_tree trunk_tree
  merged_tree=$(git merge-tree --write-tree "$1" "$2" 2>/dev/null) || { echo no; return; }
  trunk_tree=$(git rev-parse "$1^{tree}" 2>/dev/null) || { echo no; return; }
  if [ "$merged_tree" = "$trunk_tree" ]; then echo yes; else echo no; fi
}

# ==============
# OUTPUT
# ==============
# every sidecar prints the same two blocks in the same order, so the trigger docs can share
# one reading contract: telemetry is what was measured, handover is what the user runs
telemetry_open() {
  printf '\n=== @%s telemetry ===\n' "$1"
}

telemetry_line() {
  printf '%s: %s\n' "$1" "$2"
}

# HANDOVER is the block the agent fences and the user pastes; it stays copy/paste clean, so
# notes are commented rather than prose, and every line is runnable as written
handover_open() {
  printf '\n=== @%s handover ===\n' "$1"
}

# TRIGGER is the counterpart block: what the trigger runs itself against a narrow allow, never
# what the user pastes; a step earns a place here only by adding safety rather than spending it
trigger_open() {
  printf '\n=== @%s trigger ===\n' "$1"
}

handover_note() {
  printf '# %s\n' "$1"
}

handover_cmd() {
  printf '%s\n' "$1"
}

block_close() {
  printf '=====================\n'
}

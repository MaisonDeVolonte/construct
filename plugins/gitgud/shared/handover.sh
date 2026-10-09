#!/bin/bash
# ==================================================
# @file handover.sh - shared git sidecar scaffolding
# ==================================================
# @description
# - sourced by every `plugins/*/*.sh`, so the whole family shares one output shape
# - every git call here is on the permissions allow list; nothing in it mutates a repo
# - `git_default_branch` asks the remote directly, since symbolic-ref and set-head are denied
# - the handover block is the deliverable: measured here, pasted and run by the user
# - the trigger block is the narrow exception: measured here, run by the trigger as a tool call
# - a sidecar that needs to mutate emits the command instead of running it, into either block
# - `protected_incoming` names the paths a sandboxed sync cannot write, so the sync is handed over
# - a denied path leaves git's checkout half applied against an unmoved HEAD, never a clean failure
# @see .claude/skills/validate-skills/SKILL.md, plugins/operator/settings/settings.user.md, plugins/

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
# ls-remote reads the remote's own HEAD, since `remote set-head` and `symbolic-ref` are denied
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

# absorbed: merging $2 into $1 leaves $1's tree unchanged; a conflict or an old git reports no
is_absorbed() {
  local merged_tree trunk_tree
  merged_tree=$(git merge-tree --write-tree "$1" "$2" 2>/dev/null) || { echo no; return; }
  trunk_tree=$(git rev-parse "$1^{tree}" 2>/dev/null) || { echo no; return; }
  if [ "$merged_tree" = "$trunk_tree" ]; then echo yes; else echo no; fi
}

# patch-merged: does $1 already hold every patch on $2? a failed cherry read prints nothing, so no
is_patch_merged() {
  local cherry
  cherry=$(git cherry "$1" "$2" 2>/dev/null) || { echo no; return; }
  if printf '%s\n' "$cherry" | grep -q '^+'; then echo no; else echo yes; fi
}

# mirrors block-protected-paths.sh's PROTECTED list over newline-separated paths on stdin
protected_paths() {
  local boundary protected
  boundary='([/[:space:]"'"'"']|$)'
  protected="^\.claude$boundary|^\.git$boundary|^\.husky$boundary"
  protected="$protected|^plugins/operator/settings$boundary|^plugins/operator/hooks$boundary"
  protected="$protected|^plugins/operator/skills/(credentials|permissions|scripts|settings)$boundary"
  grep -E "$protected" || true
}

# incoming policy paths specifically: whatever a range would write, filtered through the same list
protected_incoming() {
  git diff --name-only "$1" 2>/dev/null | protected_paths
}

# ==============
# OUTPUT
# ==============
# every sidecar prints these two blocks, headed by its invocation name; `rerun.sh` opts out
# ==============
# CONFIG
# ==============
# a project key wins over a user key, and a missing key falls back to the caller's own default
PROJECT_CONFIG="${PROJECT_CONFIG:-$(git rev-parse --show-toplevel 2>/dev/null)/construct.config.json}"
USER_CONFIG="${USER_CONFIG:-$HOME/.construct/config.json}"

# `cfg .github.merge_method rebase` is the whole shape; every caller must require jq itself
cfg() {
  local path=$1 fallback=${2:-} value=''
  if [ -r "$PROJECT_CONFIG" ]; then
    value=$(jq -r "$path // empty" "$PROJECT_CONFIG" 2>/dev/null || true); fi
  if [ -z "$value" ] && [ -r "$USER_CONFIG" ]; then
    value=$(jq -r "$path // empty" "$USER_CONFIG" 2>/dev/null || true); fi
  printf '%s' "${value:-$fallback}"
}

# ==============
# RESOLUTION
# ==============
# resolves a handed-over path for the caller's cwd, returning nonzero so a dead path is omitted
gitgud_path() {
  local rel="$1"
  # cloner: the caller's repo is this repo, so the tracked relative path resolves as written
  if [ -f "plugins/gitgud/$rel" ]; then printf 'plugins/gitgud/%s\n' "$rel"; return 0; fi
  # installer: the plugin sits outside the caller's repo, so only CLAUDE_PLUGIN_ROOT resolves
  if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/$rel" ]; then
    printf '%s/%s\n' "${CLAUDE_PLUGIN_ROOT}" "$rel"; return 0; fi
  return 1
}

# repo-local maintainer tools ship to the cloner only, so the installer gets no path at all
repo_path() {
  [ -f "$1" ] && printf '%s\n' "$1"
}

telemetry_open() {
  printf '\n=== /%s telemetry ===\n' "$1"
}

telemetry_line() {
  printf '%s: %s\n' "$1" "$2"
}

# HANDOVER is the block the user pastes, so notes are comments and every line runs as written
handover_open() {
  printf '\n=== /%s handover ===\n' "$1"
}

# TRIGGER is the block the trigger runs itself; a step belongs here only if it adds safety
trigger_open() {
  printf '\n=== /%s trigger ===\n' "$1"
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

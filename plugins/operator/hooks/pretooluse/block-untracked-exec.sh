#!/bin/bash
# ======================================================================
# @file block-untracked-exec.sh - denies running what git has not seen
# ======================================================================
# @description
# - fires before a Bash call runs: denies executing a script no commit holds
# - a script's contents are opaque to a matcher, so provenance is the only property left to test
# - the test is two git calls: is the target tracked, and does it still match HEAD
# - a reviewed script runs; one this session wrote is handed back, which moves trust to code review
# - splits compounds on UNQUOTED `&|;` via `shared/commands.sh`, the one file this action needs
# - silent (exit 0) for everything else, so ordinary work never pays for the check
# - #1: no git dir means the premise is absent, so the check exits rather than refusing every script
# - #2: a target outside the repo is unjudgeable here, and the sandbox already bounds writes to cwd
# - #3: a launcher is matched by name, since `bash x.sh` and `./x.sh` run the same bytes
# - #4: a tracked package.json never vouches for a dependency's postinstall, so the flag decides
# - #5: scanning every token read `jq -e . file` as the shell `.` source form and denied it
# @see plugins/operator/shared/commands.sh, plugins/operator/hooks/hooks.json, plugins/operator/shared/corpus.tsv, plugins/operator/skills/permissions/permissions.sh

command -v jq >/dev/null 2>&1 || { echo "block-untracked-exec: jq missing, refusing to run unguarded" >&2; exit 2; }

# the splitter is the one shared piece; a missing copy refuses to run unguarded, like the jq guard
COMMANDS="$(dirname "${BASH_SOURCE[0]}")/../../shared/commands.sh"
[ -f "$COMMANDS" ] || { echo "block-untracked-exec: shared/commands.sh missing, refusing to run unguarded" >&2; exit 2; }
# shellcheck source=../../shared/commands.sh
. "$COMMANDS"

CMD=$(jq -r '.tool_input.command // .toolInput.command // empty')

# nothing to inspect
[ -z "$CMD" ] && exit 0

# without a repo there is no tracked set to compare against, so the premise is absent (see #1)
git rev-parse --git-dir >/dev/null 2>&1 || exit 0

deny() {
  jq -n --arg reason "$1" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $reason
    }
  }'
  exit 0
}

# a path git never stored, or stored and no longer matches, is unreviewed; existence is not tested
judge() {
  local target=$1
  [ -n "$target" ] || return 0
  # a flag is not a file, and `bash -c` is the common form that would otherwise deny
  case "$target" in -*) return 0 ;; esac
  # a path the repo does not contain is judged by the sandbox instead of by this hook (see #2)
  case "$target" in /*|"~"/*) return 0 ;; esac
  if ! git ls-files --error-unmatch "$target" >/dev/null 2>&1; then
    deny "blocked by block-untracked-exec: $target is untracked, so no commit holds it. run it yourself if you really mean to."
  fi
  if ! git diff --quiet HEAD -- "$target" 2>/dev/null; then
    deny "blocked by block-untracked-exec: $target differs from HEAD, so what runs was never reviewed. run it yourself."
  fi
}

# an install resolves its own tree from a lockfile, so the flag is the only reviewable part (see #4)
judge_install() {
  case "$2" in install|ci|i) ;; *) return 0 ;; esac
  printf '%s' "$1" | grep -q -- '--ignore-scripts' && return 0
  deny "blocked by block-untracked-exec: an install without --ignore-scripts runs postinstall. run it yourself."
}

# every launcher that hands a file to an interpreter, plus the bare `./` form (see #3)
LAUNCHER='^(bash|sh|zsh|ksh|dash|source|\.)$'

# only the FIRST token of a segment is a command, since the splitter already cut on `&|;` (see #5)
while IFS= read -r segment; do
  # shellcheck disable=SC2086
  set -- $segment
  case "$1" in
    ./*)   judge "${1#./}" ;;
    # the target is derived rather than named, so an absent Makefile is nothing to judge
    make)  [ -f Makefile ] && judge "Makefile" ;;
    npm|pnpm|yarn) judge_install "$segment" "$2" ;;
    *)
      if printf '%s' "$1" | grep -qE "$LAUNCHER"; then judge "${2#./}"; fi
      ;;
  esac
done < <(split_unquoted "$CMD")

exit 0

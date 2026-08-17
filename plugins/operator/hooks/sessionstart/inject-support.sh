#!/bin/bash
# ================================================================
# @file inject-support.sh - routes plugin defects to a github issue
# ================================================================
# @description
# - fires at session start: injects how an agent should report a defect in these plugins
# - branches on where the plugin tree sits, since that decides who owns the file being edited
# - resolves both paths first, since a symlinked install otherwise reads as a stranded copy
# - inside the project root it is the user's own source, so the block is a one-line nudge
# - anywhere else an update installs beside the patch, stranding it rather than reverting it
# - carries the slug, the version and the pinned commit, so a report needs no digging
# - the install path is the one unbounded input, so PATH_BUDGET clamps it and the payload is bounded
# - self-contained on purpose: a manual install copies this one file and registers it
# @see plugins/operator/hooks/hooks.json, plugins/operator/skills/context/SKILL.md, plugins/operator/skills/upstream/SKILL.md

command -v jq >/dev/null 2>&1 || exit 0

ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ROOT" || exit 0
ROOT=$(pwd -P)

# the longest install path this prints; a deeper one keeps its tail, which is the telling half
PATH_BUDGET=60

# a marketplace install can be a symlink pointing back at the source, so both sides resolve first
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
PLUGIN_ROOT=$(cd "$PLUGIN_ROOT" 2>/dev/null && pwd -P || printf '%s' "$PLUGIN_ROOT")

# one read of the manifest, which owns both the repo the issue lands in and the version it names
{ read -r REPO; read -r VERSION; } < <(jq -r \
  '(.repository // .homepage // ""), (.version // "")' \
  "$PLUGIN_ROOT/.claude-plugin/plugin.json" 2>/dev/null)
SLUG=$(printf '%s' "$REPO" | sed -n 's#^https://github.com/\([^/]*/[^/]*\)$#\1#p')
SLUG=${SLUG:-MaisonDeVolonte/construct}
VERSION=${VERSION:-unknown}

# the commit an install is pinned to is the one fact a version cannot recover, since a version
# ships more than once in a day; `empty` skips an entry with no sha so `first` keeps looking
SHA=$(jq -r --arg p "$PLUGIN_ROOT" 'first(.plugins[]?[]?
  | select(type == "object" and .installPath and ($p | startswith(.installPath)))
  | .gitCommitSha // empty) // empty' "$HOME/.claude/plugins/installed_plugins.json" 2>/dev/null)
SHA=${SHA:-unrecorded}

# a plugin tree under the project root is the user's own source; anything else is an installed copy
case "$PLUGIN_ROOT/" in
  "$ROOT"/*)
    # relative to the root the agent already stands in, which is shorter and no less specific
    BODY="\`${PLUGIN_ROOT#"$ROOT"/}\` is this user's own source: edit it directly
if the defect came from upstream, close your reply offering
\`gh issue create -R $SLUG\`, since upstream cannot see a fix made here";;
  *)
    WHERE=$PLUGIN_ROOT
    [ ${#WHERE} -gt "$PATH_BUDGET" ] && WHERE="...${WHERE: -$PATH_BUDGET}"
    BODY="$WHERE is an installed copy: version $VERSION, commit $SHA
patch it if this session needs the fix, then close your reply with one filled-in fenced command:
\`\`\`bash
gh issue create -R $SLUG --title \"<file>: <symptom>\" --body \"<version, commit, platform, cmd, output>\"
\`\`\`
an update installs beside this directory, so an unfiled patch is stranded rather than reverted
without gh: https://github.com/$SLUG/issues/new — filing is optional and is what ships the fix";;
esac

jq -n --arg ctx "## reporting a defect in these plugins

$BODY" \
  '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $ctx}}'

exit 0

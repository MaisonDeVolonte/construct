#!/bin/bash
# ================================================================
# @file inject-support.sh - routes plugin defects to a github issue
# ================================================================
# @description
# - fires at session start: injects how an agent should report a defect in these plugins
# - branches on where the plugin tree sits, since that decides who owns the file being edited
# - inside the project root it is the user's own source, so the block is a one-line nudge
# - anywhere else it is an install, and a local patch is stranded rather than reverted on update
# - a marketplace install is version-pinned, so an update writes a new directory beside the patch
# - carries the repo slug, the plugin version and the pinned commit, so a report needs no digging
# - the patch is never forbidden; the issue is what makes the patch reach the next release
# - self-contained on purpose: a manual install copies this one file and registers it
# @see plugins/operator/hooks/hooks.json, plugins/operator/skills/upstream/SKILL.md

command -v jq >/dev/null 2>&1 || exit 0

ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ROOT" || exit 0

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

# the repository the issue lands in, read from the manifest rather than restated here
MANIFEST="$PLUGIN_ROOT/.claude-plugin/plugin.json"
SLUG=$(jq -r '.repository // .homepage // empty' "$MANIFEST" 2>/dev/null \
  | sed -n 's#^https://github.com/\([^/]*/[^/]*\)$#\1#p')
SLUG=${SLUG:-MaisonDeVolonte/construct}
VERSION=$(jq -r '.version // "unknown"' "$MANIFEST" 2>/dev/null)

# the marketplace records the commit each install is pinned to, which is the one fact a maintainer
# cannot recover from a version alone, since a version ships more than once during a day's work
LEDGER="$HOME/.claude/plugins/installed_plugins.json"
SHA=$(jq -r --arg p "$PLUGIN_ROOT" '
  [ .plugins[]?[]?
    | select(type == "object")
    | select(.installPath != null)
    | . as $entry
    | select($p | startswith($entry.installPath))
    | .gitCommitSha // empty ]
  | first // empty' "$LEDGER" 2>/dev/null)
SHA=${SHA:-unrecorded}

# a plugin tree under the project root is the user's own source; anything else is an installed copy
case "$PLUGIN_ROOT/" in
  "$ROOT"/*) MODE=source;; *) MODE=install;;
esac

if [ "$MODE" = source ]; then
  BODY="the plugin tree at $PLUGIN_ROOT sits inside this project, so it is this user's own source
edit it directly; that is what a maintainer's checkout is for
if a defect you fix here came from upstream, say so in one line at the end of your reply
and offer the user a \`gh issue create -R $SLUG\` command, since upstream cannot see this fix"
else
  BODY="the plugin tree at $PLUGIN_ROOT is an installed copy, version $VERSION, pinned at $SHA
patch it when a session needs the fix now; a patch here is never forbidden
but an update installs a new version directory beside this one, so the patch is not reverted,
it is stranded, and the user silently stops running the code they fixed
so whenever you patch, or find a defect you cannot patch, close your reply with one fenced
\`gh issue create\` command for the user to paste, filled in, never a placeholder:
\`\`\`bash
gh issue create -R $SLUG --title \"<the file and the symptom, one line>\" --body \"...\"
\`\`\`
the body carries the version, the commit, the platform, the command that failed and its output
add the url form under it for a user without gh: https://github.com/$SLUG/issues/new
say filing is optional and that it is what gets the fix into the next release"
fi

jq -n --arg ctx "## reporting a defect in these plugins

$BODY" \
  '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $ctx}}'

exit 0

#!/bin/bash
# =============================================================================
# @file suggest-allow-rules.sh - names the allow rule a prompted command needs
# =============================================================================
# @description
# - fires before a Bash call runs: predicts the prompt, then names the rule that clears it
# - casts no vote; it prints `systemMessage` only, so the rules still decide this call (see #1)
# - #1: a hook `allow` never beats an `ask` or a `deny` rule, so a suggestion is the honest output
# - three documented shapes prompt even under a matching prefix rule, and this reads all three
# - #2: an unquoted glob beside `find`, `sort`, `sed` or `git`, since it could expand into a flag
# - #3: an exec wrapper, `watch`, `setsid`, `ionice` or `flock`, which no prefix rule auto-approves
# - #4: `find -exec` and `find -delete`, the two forms `Bash(find *)` is documented not to cover
# - appends one json line per hit to `.construct/operator/permissions/asked.jsonl` for the audit
# - splits compounds on unquoted `&|;` via `shared/commands.sh`, so a quoted `*` stays quoted
# - silent (exit 0) for everything else, so ordinary work never pays for the check
# @see plugins/operator/hooks/hooks.json, plugins/operator/shared/commands.sh, plugins/operator/skills/permissions/permissions.sh

command -v jq >/dev/null 2>&1 || { echo "suggest-allow-rules: jq missing, refusing to run unguarded" >&2; exit 2; }

COMMANDS="$(dirname "${BASH_SOURCE[0]}")/../../shared/commands.sh"
[ -f "$COMMANDS" ] || { echo "suggest-allow-rules: shared/commands.sh missing, refusing to run unguarded" >&2; exit 2; }
# shellcheck source=../../shared/commands.sh
. "$COMMANDS"

CMD=$(jq -r '.tool_input.command // .toolInput.command // empty')

# nothing to inspect
[ -z "$CMD" ] && exit 0

LEDGER="${CLAUDE_PROJECT_DIR:-.}/.construct/operator/permissions/asked.jsonl"

# the documented shapes, each one a command that prompts even when a prefix rule matches it
GLOB_VERBS='find|sort|sed|git'
WRAPPERS='watch|setsid|ionice|flock'

# a quoted `*` is data the shell never expands, so blank every quoted span before the glob test
blank_quoted() {
  printf '%s\n' "$1" | awk '
    BEGIN { sq = 0; dq = 0 }
    {
      out = ""
      for (i = 1; i <= length($0); i++) {
        c = substr($0, i, 1)
        if (c == "\"" && !sq) { dq = !dq; out = out c; continue }
        if (c == "\047" && !dq) { sq = !sq; out = out c; continue }
        if (sq || dq) { out = out "Q"; continue }
        out = out c
      }
      print out
    }'
}

# the verb is the first token that is not a leading VAR=value assignment
head_verb() {
  printf '%s\n' "$1" | awk '
    {
      for (i = 1; i <= NF; i++) {
        if ($i ~ /^[A-Za-z_][A-Za-z0-9_]*=/) { continue }
        sub(/^.*\//, "", $i)
        print $i
        exit
      }
    }'
}

HITS=""
while IFS= read -r segment; do
  # trim both ends, since split_unquoted keeps the spacing that surrounded each separator
  segment="$(printf '%s' "$segment" | awk '{$1=$1; print}')"
  [ -z "$segment" ] && continue

  verb="$(head_verb "$segment")"
  [ -z "$verb" ] && continue
  bare="$(blank_quoted "$segment")"
  reason=""

  # the glob survives the blanking only when the shell would expand it (see #2)
  if printf '%s' "$verb" | grep -qE "^($GLOB_VERBS)$" \
     && printf '%s' "$bare" | grep -q '[*?]'; then
    reason="an unquoted glob beside $verb, which could expand into a flag"
  fi

  # an exec wrapper runs its argument, so no prefix rule on the wrapper can approve it (see #3)
  if [ -z "$reason" ] && printf '%s' "$verb" | grep -qE "^($WRAPPERS)$"; then
    reason="$verb runs its argument, so a prefix rule never auto-approves it"
  fi

  # these find forms write, and the docs state Bash(find *) does not reach them (see #4)
  if [ -z "$reason" ] && [ "$verb" = "find" ] \
     && printf '%s' "$bare" | grep -qE '(^|[[:space:]])(-exec|-execdir|-delete|-ok|-okdir)([[:space:]]|$)'; then
    reason="find with an exec or delete action, which Bash(find *) does not cover"
  fi

  [ -z "$reason" ] && continue

  HITS="$HITS$segment"$'\t'"$reason"$'\n'
done < <(split_unquoted "$CMD")

[ -z "$HITS" ] && exit 0

# one paste-ready rule per offending segment, exact-match on the string the shell was handed
MSG="this command prompts; add the rule to \`allow\` in .claude/settings.json to clear it next time:"
STAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
mkdir -p "$(dirname "$LEDGER")" 2>/dev/null

while IFS=$'\t' read -r segment reason; do
  [ -z "$segment" ] && continue
  MSG="$MSG"$'\n'"  \"Bash($segment)\"  # $reason"
  jq -nc --arg ts "$STAMP" --arg rule "Bash($segment)" --arg reason "$reason" --arg cmd "$CMD" \
    '{ts: $ts, rule: $rule, reason: $reason, command: $cmd}' >> "$LEDGER" 2>/dev/null
done <<< "$HITS"

jq -n --arg msg "$MSG" '{systemMessage: $msg}'
exit 0

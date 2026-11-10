#!/bin/bash
# =========================================================================
# @file block-destructive-airtable.sh - denies airtable updates and deletes
# =========================================================================
# @description
# - fires before a Bash call runs: judges only command strings that name an airtable host
# - denies a DELETE, PUT or PATCH method anywhere in the string, literal or variable
# - denies the flags that imply or hide a method: -T, -K, --variable, --expand-*, an override header
# - denies a method flag whose value is not a plain GET, POST or HEAD, such as a quote-split one
# - denies inline code that sends one: requests.delete(, method: 'PATCH', request('PUT'
# - GET and POST pass: reads, and creating bases, tables and fields
# - a host the string never names literally ($H, `cmd`) passes unseen; the pat still limits it
# - a script's own requests never reach this check; block-untracked-exec and the pat cover them
# - silent (exit 0) for everything else, so ordinary work never pays more than one grep
# - self-contained on purpose: a manual install copies this one file and registers it
# @see plugins/operator/hooks/hooks.json, plugins/operator/hooks/pretooluse/block-destructive-git.sh

command -v jq >/dev/null 2>&1 || { echo "block-destructive-airtable: jq missing, refusing to run unguarded" >&2; exit 2; }

CMD=$(jq -r '.tool_input.command // .toolInput.command // empty')

# nothing to inspect
[ -z "$CMD" ] && exit 0

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

# only strings naming airtable are judged
printf '%s' "$CMD" | grep -Eiq 'airtable\.com' || exit 0

M='([Dd][Ee][Ll][Ee][Tt][Ee]|[Pp][Uu][Tt]|[Pp][Aa][Tt][Cc][Hh])'

# explicit method, quoted or not: -X DELETE, -sSX PUT, --request=DELETE, wget --method=PATCH
if printf '%s' "$CMD" | grep -Eq "(^|[[:space:]])(-[A-Za-z]*X|--request|--method)[[:space:]=]*[\"']?${M}([^A-Za-z]|\$)"; then
  deny "blocked by block-destructive-airtable: DELETE, PUT or PATCH against airtable. run it yourself if you really mean to."
fi

# a method this check cannot read: -X "\$M", -X \`cmd\`
if printf '%s' "$CMD" | grep -Eq "(^|[[:space:]])(-[A-Za-z]*X|--request|--method)[[:space:]=]*[\"']?[\$\`]"; then
  deny "blocked by block-destructive-airtable: a variable request method against airtable. run it yourself if you really mean to."
fi

# httpie and xh take the method as a bare word: http PATCH url
if printf '%s' "$CMD" | grep -Eq "(^|[[:space:]])(http|https|xh|xhs)[[:space:]]+${M}([[:space:]]|\$)"; then
  deny "blocked by block-destructive-airtable: DELETE, PUT or PATCH against airtable. run it yourself if you really mean to."
fi

# any other method value is denied, so a quote-split -X D"ELETE" cannot pass as unreadable
if printf '%s' "$CMD" | grep -oE "(^|[[:space:]])(-[A-Za-z]*X|--request|--method)[[:space:]=]*[^[:space:]]*" \
   | grep -Eivq "(X|--request|--method)[[:space:]=]*[\"']?(GET|POST|HEAD)[\"']?\$"; then
  deny "blocked by block-destructive-airtable: a request method that is not a plain GET, POST or HEAD. run it yourself if you really mean to."
fi

# inline code: requests.delete(, axios.patch(, fetch(url, {method: 'DELETE'}), request('PUT', url)
if printf '%s' "$CMD" | grep -Eiq "\.(delete|put|patch)[[:space:]]*\(" \
   || printf '%s' "$CMD" | grep -Eiq "method[\"']?[[:space:]]*[:=][[:space:]]*[\"']?(delete|put|patch)([^A-Za-z]|\$)" \
   || printf '%s' "$CMD" | grep -Eiq "request[[:space:]]*\([[:space:]]*[\"'](delete|put|patch)[\"']"; then
  deny "blocked by block-destructive-airtable: inline code sending DELETE, PUT or PATCH to airtable. run it yourself if you really mean to."
fi

# -T uploads with PUT; -K reads a config that sets any method; --variable and --expand-* build one
# only no-value flags may precede T or K, so -XPOST passes; a glued value (-Tbody.json) is caught
if printf '%s' "$CMD" | grep -Eq '(^|[[:space:]])(-[sSLfkiIvgGjlnNOqRaBp46]*[TK][^[:space:]]*|--upload-file|--config|--variable|--expand-[a-z-]+)([[:space:]=]|$)'; then
  deny "blocked by block-destructive-airtable: a curl flag that sets or hides the method (-T, -K, --variable, --expand-*). run it yourself if you really mean to."
fi

# the one POST that destroys: the sync api replaces a synced table's rows with the csv it is sent
if printf '%s' "$CMD" | grep -Eq '/sync/'; then
  deny "blocked by block-destructive-airtable: the sync api overwrites a synced table. run it yourself if you really mean to."
fi

# a method override header turns an allowed POST into anything
if printf '%s' "$CMD" | grep -Eiq 'method-override'; then
  deny "blocked by block-destructive-airtable: a method override header against airtable. run it yourself if you really mean to."
fi

exit 0

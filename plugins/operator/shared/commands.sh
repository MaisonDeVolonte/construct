#!/bin/bash
# ============================================================
# @file commands.sh - splits commands on unquoted separators
# ============================================================
# @description
# - sourced, never run; a hook calls `split_unquoted "$CMD"` and reads one segment per line
# - splits a compound command on UNQUOTED `&`, `|` and `;` only, one segment per line out
# - a quoted metacharacter stays inside its segment, so a per-segment test still means something
# - `tr '&|;'` split inside quotes once, and a pipe-delimited sed tore its own command in half
# - the interpreter landed in one segment and its policy path in another, and neither test fired
# - a `|` delimiter is the idiomatic sed choice exactly when the strings rewritten are paths
# @see plugins/operator/hooks/pretooluse/block-protected-paths.sh, plugins/operator/hooks/pretooluse/block-outside-moves.sh, plugins/operator/shared/corpus.tsv

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  echo "fatal: source this file from a hook, do not run it" >&2; exit 1
fi

split_unquoted() {
  printf '%s\n' "$1" | awk '
    BEGIN { sq = 0; dq = 0 }
    {
      out = ""
      for (i = 1; i <= length($0); i++) {
        c = substr($0, i, 1)
        if (c == "\"" && !sq) { dq = !dq; out = out c; continue }
        if (c == "\047" && !dq) { sq = !sq; out = out c; continue }
        if (!sq && !dq && (c == "&" || c == "|" || c == ";")) { out = out "\n"; continue }
        out = out c
      }
      print out
    }'
}

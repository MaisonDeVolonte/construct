#!/bin/bash
# ==============================================================
# @file context.sh - literal session context accounting sidecar
# ==============================================================
# @description
# PAIR
# - sidecar for `/operator:context` — reports what literally reached this session's context
# - it answers one question: did the payload a hook emitted actually land, byte for byte
# - a hook that runs, exits 0 and prints perfectly still injects nothing once it passes the cap
# SOURCE
# - reads this session's own transcript, the harness's own record of what it accepted
# - `hook_success` carries each hook's raw stdout; `hook_additional_context` carries what landed
# - a declared payload matches a landed one by exact string equality, never by position
# - so a drop is measured rather than inferred, which is why this reads a transcript at all
# - never re-runs a hook: a replay proves what a script emits now, not what this session received
# RUN
# - read-only: it measures and reports, and every repair is the user's to apply
# - `--quick` reports inline and writes nothing; `--strict` promotes warnings; `--keep` holds tmp
# - exits 1 on any error, so a dropped payload fails a ci run rather than reading as a clean one
# @see plugins/operator/skills/context/SKILL.md, plugins/operator/hooks/sessionstart/, plugins/operator/hooks/hooks.json, README.md

set -euo pipefail

# the doc is read only after this has already run, so help is refused here or not at all; the doc's
# own '## Help' section owns the output, which is why this prints a marker rather than a usage text
case " $* " in *" --help "*|*" -h "*) echo "help: requested"; exit 0;; esac

# the smoke case proves this file parses and its guards return; /test-skills reads the sources,
# the @see paths and the tool guards statically, so nothing here runs a step of the skill
case " $* " in *" --test "*) echo "test: ok"; exit 0;; esac

# ==============
# PREFLIGHT
# ==============
# the injectors sit beside this file, not beside the repo being measured: resolve them before
# anything cds to a repo root, since BASH_SOURCE arrives relative and would follow that cd
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)
INJECTORS="$HERE/../../hooks/sessionstart"

command -v jq >/dev/null 2>&1 || { echo "fatal: jq is required" >&2; exit 1; }

QUICK=0
STRICT=0
KEEP=0
for arg in "$@"; do
  case "$arg" in
    --quick) QUICK=1;;
    --strict) STRICT=1;;
    --keep) KEEP=1;;
    *) echo "fatal: unknown flag $arg" >&2; exit 1;;
  esac
done

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "fatal: not a git repository" >&2; exit 1; fi
ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"

# the documented harness limits: one hook payload is capped, and the overflow becomes a preview
CAP=10000
PREVIEW=2048
# a payload this close to the cap is one edit from crossing it, so it is named before it does
MARGIN=500
TILDE='~'

# repo-local scratch: the sandbox denies writes outside cwd, and macos mktemp ignores TMPDIR
TMPROOT="$ROOT/tmp"
TMPTAG=$(basename "${BASH_SOURCE[0]}" .sh)
mkdir -p "$TMPROOT"
FINDINGS=$(mktemp "$TMPROOT/$TMPTAG-findings.XXXXXX")
SCRATCH=$(mktemp -d "$TMPROOT/$TMPTAG-scratch.XXXXXX")
# a failed run leaves scratch behind to read; --keep does the same after a clean one
cleanup() { st=$?; if [ "$KEEP" -eq 0 ] && [ "$st" -eq 0 ]; then rm -rf "$FINDINGS" "$SCRATCH"; fi; }
trap cleanup EXIT

# a finding leads with its kind rather than its script, so the artifact stays greppable by kind
# and two injectors failing the same way sort together instead of by alphabet
err()  { printf 'ERROR|%s|%s|%s\n' "$1" "$2" "$3" >> "$FINDINGS"; }
warn() { printf 'WARN|%s|%s|%s\n' "$1" "$2" "$3" >> "$FINDINGS"; }

# ==============
# TRANSCRIPT
#   the harness's own record of this session, the only thing that can prove what it accepted
# ==============
# the session id names the file; the project directory is slugified from cwd by a rule this does
# not restate, so the id is searched for and the slug never has to be reproduced here
SESSION="${CLAUDE_CODE_SESSION_ID:-${CLAUDE_SESSION_ID:-}}"
PROJECTS="$HOME/.claude/projects"
TRANSCRIPT=""
if [ -n "$SESSION" ] && [ -d "$PROJECTS" ]; then
  TRANSCRIPT=$(find "$PROJECTS" -maxdepth 2 -name "$SESSION.jsonl" -type f 2>/dev/null | head -1)
fi

if [ -z "$TRANSCRIPT" ]; then
  cat <<EOF

=== context.sh audit ===
session: ${SESSION:-unset}
transcript: none reachable
--- findings ---
ERROR no_transcript  nothing was measured, so no claim below would be proven
- the id comes from \$CLAUDE_CODE_SESSION_ID, which a nested or headless run may not export
- without it this skill could only replay hooks, which proves a script and never a session
============================
EOF
  exit 1
fi

# ==============
# TIER 1 — the hook boundary
#   declared is what a hook wrote to stdout; landed is what the harness put in context
# ==============
# one pass, slurped: the landed set has to be whole before a declared payload can be matched to it
# a hook printing bare text injects that text, so a payload that is not json is read as declared
BOUNDARY='
[ .[] | select(.type == "attachment") | .attachment ] as $att
| [ $att[] | select(.type == "hook_additional_context") | .content[]? | select(type == "string") ]
  as $landed
| [ $att[]
| select(.type == "hook_success")
| (.stdout // "") as $out
| (($out | try (fromjson | .hookSpecificOutput.additionalContext) catch null)
   // (if ($out | test("^[[:space:]]*[{[]")) then null else ($out | sub("^\\s+"; "")
   | sub("\\s+$"; "")) end)) as $decl
| { event: (.hookEvent // "?"),
    script: ((.command // "?") | split("/") | last | split(" ") | first),
    stdout: ($out | length),
    dchars: (if $decl == null or $decl == "" then 0 else ($decl | length) end),
    hit: (if $decl == null or $decl == "" then false else any($landed[]; . == $decl) end) } ]
| .[]
| [ .event, .script, (.stdout | tostring), (.dchars | tostring),
    (if .dchars == 0 then "none" elif .hit then "landed" else "dropped" end) ]
| @tsv'
jq -rs "$BOUNDARY" "$TRANSCRIPT" > "$SCRATCH/boundary" 2>/dev/null || true

# a hook that errored injected its error instead of its payload: context spent on nothing
HOOK_ERRORS='
[ .[] | select(.type == "attachment") | .attachment
| select(.type == "hook_blocking_error" or .type == "hook_non_blocking_error") ]
| group_by(.type)
| .[] | [ .[0].type, (length | tostring) ] | @tsv'
jq -rs "$HOOK_ERRORS" "$TRANSCRIPT" > "$SCRATCH/hook_errors" 2>/dev/null || true

# how often the session-start batch ran; a resume replays it and lands every payload again
BATCHES='
[ .[] | select(.type == "attachment") | .attachment
| select(.type == "hook_additional_context")
| select((.hookEvent // "") == "SessionStart") ] | length'
BATCHES=$(jq -rs "$BATCHES" "$TRANSCRIPT" 2>/dev/null || echo 0)
BATCHES=${BATCHES:-0}

# ==============
# TIER 2 — everything else the harness put in context
#   not a hook and not a file read, so nothing in the plugin tree can budget any of it
# ==============
HARNESS='
def size:
  if (.content? | type) == "string" then (.content | length)
  elif (.content? | type) == "array" then ([ .content[] | tostring | length ] | add // 0)
  elif (.addedLines? | type) == "array" then ([ .addedLines[] | tostring | length ] | add // 0)
  else (tostring | length) end;
[ .[] | select(.type == "attachment") | .attachment
| select(.type != "hook_success" and .type != "hook_additional_context")
| { kind: (.type // "?"), chars: size } ]
| group_by(.kind)
| map({ kind: .[0].kind, count: length, chars: ([ .[].chars ] | add // 0) })
| sort_by(-.chars)
| .[] | [ .kind, (.count | tostring), (.chars | tostring) ] | @tsv'
jq -rs "$HARNESS" "$TRANSCRIPT" > "$SCRATCH/harness" 2>/dev/null || true

# ==============
# TIER 3 — the ceiling
#   the api's own count of what it was sent, the one figure no local measure can fake
# ==============
USAGE='
[ .[] | select(.type == "assistant") | .message.usage? | select(. != null) ] | last
| if . == null then "unrecorded" else
  ((.input_tokens // 0) + (.cache_read_input_tokens // 0)
   + (.cache_creation_input_tokens // 0) | tostring)
  + " in context at the last turn — " + ((.cache_read_input_tokens // 0) | tostring)
  + " cached, " + ((.cache_creation_input_tokens // 0) | tostring)
  + " new, " + ((.input_tokens // 0) | tostring) + " fresh" end'
TOKENS=$(jq -rs "$USAGE" "$TRANSCRIPT" 2>/dev/null || echo unrecorded)
TOKENS=${TOKENS:-unrecorded}

# ==============
# GRADE
# ==============
# each injector's own budget, read from its source rather than restated here; an injector with no
# budget line has no cap of any kind, which is the one shape the harness truncates without saying
budget_of() {
  local file value
  file="$INJECTORS/$1"
  [ -f "$file" ] || { printf 'unknown'; return; }
  value=$(grep -oE '^[A-Z_]*(BUDGET|MAX_ROWS|LIMIT)[A-Z_]*=[0-9]+' "$file" 2>/dev/null | head -1)
  if [ -z "$value" ]; then printf 'none'; else printf '%s' "${value#*=}"; fi
}

# the budget guards the body, the cap judges the escaped stdout, and json escaping sits between
# them; a budget projecting past the cap is a drop nobody sees until the input grows into it
grade_budget() {
  local script=$1 stdout=$2 dchars=$3 budget projected slack
  budget=$(budget_of "$script")
  if [ "$budget" = unknown ]; then return 0; fi
  if [ "$budget" = none ]; then
    warn uncapped "$script" "no budget in its source, so a longer input truncates silently"
    return 0
  fi
  # a row cap counts rows rather than characters, so no projection can be made from it
  if [ "$budget" -lt 100 ]; then return 0; fi
  projected=$(( budget * stdout / dchars ))
  slack=$(( CAP - projected ))
  if [ "$slack" -lt 0 ]; then
    err budget "$script" "a full $budget-char budget escapes to $projected stdout, past $CAP"
  elif [ "$slack" -lt "$MARGIN" ]; then
    warn budget "$script" "a full $budget-char budget escapes to $projected, $slack under $CAP"
  fi
}

INJECTED=0
PAYLOADS=0
while IFS=$'\t' read -r event script stdout dchars verdict; do
  [ -n "${script:-}" ] || continue
  headroom=$((CAP - stdout))

  if [ "$verdict" = dropped ]; then
    err dropped "$script" "declared $dchars chars on $event and none of them reached context"
  elif [ "$verdict" = landed ]; then
    INJECTED=$((INJECTED + dchars)); PAYLOADS=$((PAYLOADS + 1))
  fi

  if [ "$stdout" -ge "$CAP" ]; then
    err capped "$script" "stdout is $stdout, past $CAP; the rest became a $PREVIEW-byte preview"
  elif [ "$headroom" -lt "$MARGIN" ] && [ "$verdict" != none ]; then
    warn margin "$script" "stdout is $stdout, only $headroom under the $CAP cap"
  fi

  if [ "$event" = SessionStart ] && [ "$dchars" -gt 0 ]; then
    grade_budget "$script" "$stdout" "$dchars"
  fi
done < "$SCRATCH/boundary"

while IFS=$'\t' read -r kind count; do
  [ -n "${kind:-}" ] || continue
  warn hook_error "$kind" "$count hook run(s) injected an error instead of a payload"
done < "$SCRATCH/hook_errors"

if [ "$BATCHES" -gt 1 ]; then
  warn resume session "$BATCHES session-start batches here, so each payload landed that many times"
fi

# ==============
# TELEMETRY
# ==============
ERRORS=$(grep -c '^ERROR|' "$FINDINGS" || true)
WARNINGS=$(grep -c '^WARN|' "$FINDINGS" || true)
ERRORS=${ERRORS:-0}; WARNINGS=${WARNINGS:-0}
HARNESS_TOTAL=$(awk -F'\t' '{ t += $3 } END { print t + 0 }' "$SCRATCH/harness")
HARNESS_KINDS=$(wc -l < "$SCRATCH/harness" | tr -d ' ')

# audit: one file per day per kind, so two triggers on the same day never interleave one file
# reported, never created: the sidecar names the path and the count, the agent writes the entry
TODAYS_AUDIT=".construct/operator/context/$(date +%Y-%m-%d).md"
if [ -f "$ROOT/$TODAYS_AUDIT" ];
then AUDIT_COUNT=$(grep -c '^## Context Audit #' "$ROOT/$TODAYS_AUDIT" || true)
else AUDIT_COUNT=0; fi
AUDIT_COUNT=${AUDIT_COUNT:-0}

if [ "$QUICK" -eq 1 ];
then MODE="quick — report inline, write nothing"; AUDIT_FILE=none
else MODE="audit — append to audit_file"; AUDIT_FILE=$TODAYS_AUDIT; fi

cat <<EOF

=== context.sh audit ===
mode: $MODE
audit_file: $AUDIT_FILE
audit_count: $AUDIT_COUNT
next_audit: $((AUDIT_COUNT + 1))
timestamp: $(date '+%Y-%m-%d %H:%M')
session: $SESSION
transcript: ${TRANSCRIPT/#$HOME/$TILDE}
cap: $CAP chars per hook payload, then a $PREVIEW-byte preview instead
batches: $BATCHES session-start batch(es) recorded
tokens: $TOKENS
injected: $INJECTED chars over $PAYLOADS landed payload(s)
harness: $HARNESS_TOTAL chars over $HARNESS_KINDS attachment kind(s)
errors: $ERRORS
warnings: $WARNINGS
--- what the hooks put in context ---
EOF

if [ ! -s "$SCRATCH/boundary" ]; then
  echo "none — no hook_success record in this transcript, so no hook has run yet"
else
  printf '%-13s %-24s %8s %9s %9s %s\n' event script stdout declared headroom verdict
  awk -F'\t' -v cap="$CAP" \
    '{ printf "%-13s %-24s %8s %9s %9s %s\n", $1, $2, $3, $4, cap - $3, $5 }' "$SCRATCH/boundary"
fi

echo "--- what the harness put in context ---"
if [ ! -s "$SCRATCH/harness" ]; then
  echo "none — nothing but hooks has been attached to this session yet"
else
  printf '%-28s %7s %9s\n' kind count chars
  awk -F'\t' '{ printf "%-28s %7s %9s\n", $1, $2, $3 }' "$SCRATCH/harness"
fi

echo "--- findings ---"
if [ "$ERRORS" -eq 0 ] && [ "$WARNINGS" -eq 0 ]; then
  echo "none — every payload a hook declared reached context whole, with room under the cap"
else
  sort -t'|' -k1,1 -k2,2 "$FINDINGS" \
    | awk -F'|' '{ printf "%-5s %-11s %-22s %s\n", $1, $2, $3, $4 }'
fi

cat <<'EOF'
--- what this audit cannot tell you ---
- it reads what the harness recorded, so a payload dropped before the record is invisible to it
- the cap is applied by the harness to stdout, so a budget set on the pre-json body is a guess
- a landed payload is proven present, never proven read; context is not attention
- attachments outside `content` are measured at their serialized size, which overstates them
- tokens come from the last assistant turn, so this run's own output is not counted in them yet
- a compact rewrites context wholesale, and nothing here recovers what the summary dropped
- the system prompt, the tool schemas and the styles never reach the transcript, so none is counted
============================
EOF

if [ "$ERRORS" -gt 0 ]; then exit 1; fi
if [ "$STRICT" -eq 1 ] && [ "$WARNINGS" -gt 0 ]; then exit 1; fi
exit 0

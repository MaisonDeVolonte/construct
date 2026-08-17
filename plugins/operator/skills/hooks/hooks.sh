#!/bin/bash
# =======================================================
# @file hooks.sh - hook registration and liveness sidecar
# =======================================================
# @description
# PAIR
# - sidecar for `/operator:hooks` — reports whether this machine's hooks are registered and live
# - it answers one question: will the harness accept every hook block, and did they actually fire
# SOURCE
# - grades each settings scope and each plugin's hooks.json as json, never as text
# - a matcher that is not a string makes the harness skip that whole FILE, every event in it
# - upstream #75081: interactive sessions dialog it, `claude -p` drops the file in silence
# - liveness reads this session's transcript, the harness's own record of each hook that ran
# RUN
# - read-only: it measures and reports, and every repair is the user's to apply
# - `--quick` reports inline and writes nothing; `--strict` promotes warnings; `--keep` holds tmp
# - exits 1 on any error, so an unloadable scope fails a ci run rather than reading as a clean one
# @see plugins/operator/skills/hooks/SKILL.md, plugins/operator/hooks/hooks.json, plugins/operator/skills/context/context.sh, README.md

set -euo pipefail

# the doc is read only after this has already run, so help is refused here or not at all; the doc's
# own '## Help' section owns the output, which is why this prints a marker rather than a usage text
case " $* " in *" --help "*|*" -h "*) echo "help: requested"; exit 0;; esac

# ==============
# PREFLIGHT
# ==============
command -v jq >/dev/null 2>&1 || { echo "fatal: jq is required" >&2; exit 1; }

QUICK=0
STRICT=0
KEEP=0
# a bare path grades one candidate file beside the real scopes, which is how a ci run and a
# paste-in-progress get checked without either one being installed anywhere first
EXTRA=()
for arg in "$@"; do
  case "$arg" in
    --quick) QUICK=1;;
    --strict) STRICT=1;;
    --keep) KEEP=1;;
    --*) echo "fatal: unknown flag $arg" >&2; exit 1;;
    *) EXTRA+=("$arg");;
  esac
done

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "fatal: not a git repository" >&2; exit 1; fi
ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"

TILDE='~'

# repo-local scratch: the sandbox denies writes outside cwd, and macos mktemp ignores TMPDIR
TMPROOT="$ROOT/tmp"
TMPTAG=$(basename "${BASH_SOURCE[0]}" .sh)
mkdir -p "$TMPROOT"
FINDINGS=$(mktemp "$TMPROOT/$TMPTAG-findings.XXXXXX")
SCRATCH=$(mktemp -d "$TMPROOT/$TMPTAG-scratch.XXXXXX")
cleanup() { st=$?; if [ "$KEEP" -eq 0 ] && [ "$st" -eq 0 ]; then rm -rf "$FINDINGS" "$SCRATCH"; fi; }
trap cleanup EXIT

# a finding leads with its kind rather than its file, so two scopes failing alike sort together
err()  { printf 'ERROR|%s|%s|%s\n' "$1" "$2" "$3" >> "$FINDINGS"; }
warn() { printf 'WARN|%s|%s|%s\n' "$1" "$2" "$3" >> "$FINDINGS"; }

: > "$SCRATCH/groups"
: > "$SCRATCH/commands"
: > "$SCRATCH/files"

# ==============
# SOURCES
#   every file the harness reads a hooks block out of, project scope before user scope
# ==============
# a plugin's hooks.json is the suite's own registration; a settings scope is the operator's
add_source() {
  [ -f "$1" ] || return 0
  printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> "$SCRATCH/files"
}

add_source ".claude/settings.json" scope "$ROOT"
add_source ".claude/settings.local.json" scope "$ROOT"
add_source "$HOME/.claude/settings.json" scope "$ROOT"
add_source "$HOME/.claude/settings.local.json" scope "$ROOT"

while IFS= read -r manifest; do
  [ -n "$manifest" ] || continue
  add_source "$manifest" plugin "$(dirname "$(dirname "$manifest")")"
done < <(find plugins -maxdepth 3 -name hooks.json -type f 2>/dev/null | sort)

# a template ships to a user's scope verbatim, so a bad matcher in one is a bad matcher on install
while IFS= read -r template; do
  [ -n "$template" ] || continue
  add_source "$template" template "$ROOT"
done < <(find plugins -path '*/settings/*.json' -type f 2>/dev/null | sort)

for candidate in ${EXTRA+"${EXTRA[@]}"}; do
  if [ ! -f "$candidate" ]; then
    echo "fatal: no such file $candidate" >&2; exit 1
  fi
  add_source "$candidate" candidate "$ROOT"
done

# ==============
# PARSE
#   one row per hook group, one row per command, both keyed back to the file they came from
# ==============
GROUP_Q='
(.hooks // {}) | to_entries[] as $event
| ($event.value | if type == "array" then . else [] end) | to_entries[] as $group
| [ $event.key,
    ($group.key | tostring),
    (if ($group.value | type) != "object" then "malformed"
     elif ($group.value | has("matcher")) then ($group.value.matcher | type)
     else "absent" end),
    (if (($group.value | type) == "object" and ($group.value.matcher? | type) == "string")
     then $group.value.matcher else "" end),
    (($group.value.hooks? // []) | length | tostring) ]
| join("")'

COMMANDS='
(.hooks // {}) | to_entries[] as $event
| ($event.value | if type == "array" then . else [] end) | to_entries[] as $group
| (($group.value.hooks? // [])[] | select(type == "object"))
| [ $event.key, ($group.key | tostring), (.type // "?"), (.command // "") ]
| join("")'

SCOPES=0
while IFS=$'\t' read -r file kind base; do
  [ -n "${file:-}" ] || continue
  SCOPES=$((SCOPES + 1))
  printf '%s\n' "$kind" >> "$SCRATCH/kinds"
  if ! jq empty "$file" >/dev/null 2>&1; then
    err unparseable "$(basename "$file")" "not valid json, so the harness reads none of it"
    continue
  fi
  jq -r "$GROUP_Q" "$file" 2>/dev/null \
    | awk -F'\037' -v f="$file" -v OFS='\037' '{ print f, $0 }' >> "$SCRATCH/groups" || true
  jq -r "$COMMANDS" "$file" 2>/dev/null \
    | awk -F'\037' -v f="$file" -v b="$base" -v OFS='\037' '{ print f, b, $0 }' >> "$SCRATCH/commands" || true
done < "$SCRATCH/files"

# ==============
# GRADE — registration
#   the matcher rule is the whole of #75081: a non-string skips the file, silently under -p
# ==============
# an invalid regex is graded apart from a non-string: 2.1.221 loads a bare `*` and drops an object
valid_regex() {
  printf '' | grep -Eq "$1" 2>/dev/null
  [ "$?" -ne 2 ]
}

GROUPS_SEEN=0
while IFS=$'\037' read -r file event index mtype mvalue nhooks; do
  [ -n "${file:-}" ] || continue
  GROUPS_SEEN=$((GROUPS_SEEN + 1))
  short=$(basename "$file")
  where="$short:$event.$index"

  case "$mtype" in
    malformed)
      err malformed "$where" "the group is not an object, so the harness rejects the file" ;;
    absent|string) ;;
    *)
      err matcher "$where" "matcher is $mtype, expected string; the whole file is skipped" ;;
  esac

  if [ "$mtype" = string ] && [ -n "$mvalue" ] && ! valid_regex "$mvalue"; then
    warn regex "$where" "matcher '$mvalue' is not a valid regex; use an empty string to match all"
  fi

  if [ "${nhooks:-0}" -eq 0 ]; then
    warn empty "$where" "the group registers no hooks, so the matcher guards nothing"
  fi
done < "$SCRATCH/groups"

# an action file is one that sits under a plugin's own hooks/ tree, never under skills/hooks/
hook_actions() {
  find plugins -mindepth 2 -maxdepth 2 -type d -name hooks 2>/dev/null | sort \
    | while IFS= read -r dir; do find "$dir" -name '*.sh' -type f 2>/dev/null; done | sort
}

# ==============
# GRADE — the actions each command names
#   a rename that misses hooks.json unregisters an action without touching it
# ==============
ACTIONS=0
: > "$SCRATCH/registered"
while IFS=$'\037' read -r file base event index htype command; do
  [ -n "${file:-}" ] || continue
  short=$(basename "$file")
  where="$short:$event.$index"

  if [ "$htype" != command ]; then
    warn type "$where" "hook type is '$htype', and only 'command' runs anything"
    continue
  fi
  if [ -z "$command" ]; then
    err empty_command "$where" "the hook entry names no command at all"
    continue
  fi

  # only a statically resolvable path is graded; anything else reports unresolved, never missing
  path=${command%% *}
  path=${path#\"}; path=${path%\"}
  case "$path" in
    *'${CLAUDE_PLUGIN_ROOT}'*) path="${base}${path#*\}}";;
    '$CLAUDE_PLUGIN_ROOT'*)    path="${base}${path#\$CLAUDE_PLUGIN_ROOT}";;
    /*|./*|plugins/*) ;;
    *) warn unresolved "$where" "names no path this can grade: ${path:0:40}"; continue;;
  esac

  ACTIONS=$((ACTIONS + 1))
  printf '%s\n' "$path" >> "$SCRATCH/registered"
  if [ ! -f "$path" ]; then
    err missing "$where" "registers $(basename "$path"), which does not exist"
  elif [ ! -x "$path" ]; then
    warn not_executable "$where" "$(basename "$path") is registered but not executable"
  fi
done < "$SCRATCH/commands"

# an action nobody registers never runs, and nothing in a session says so
ORPHANS=0
while IFS= read -r action; do
  [ -n "$action" ] || continue
  if ! grep -qxF "$action" "$SCRATCH/registered" 2>/dev/null; then
    ORPHANS=$((ORPHANS + 1))
    warn orphan "$(basename "$action")" "sits under hooks/ but no hooks.json registers it"
  fi
done < <(hook_actions)

# ==============
# GRADE — verdicts
#   #77212 and #62437 both leave `deny` standing, so a blocker that asks is a blocker that may not
# ==============
BLOCKERS=0
while IFS= read -r action; do
  [ -n "$action" ] || continue
  grep -q 'permissionDecision' "$action" 2>/dev/null || continue
  BLOCKERS=$((BLOCKERS + 1))
  if grep -qE '"permissionDecision"[[:space:]]*:[[:space:]]*"ask"' "$action" 2>/dev/null; then
    warn ask_verdict "$(basename "$action")" "emits 'ask', which bypassPermissions may auto-approve"
  fi
done < <(hook_actions)

# ==============
# LIVENESS
#   registration is a claim; the transcript is the only record that a hook actually ran
# ==============
SESSION="${CLAUDE_CODE_SESSION_ID:-${CLAUDE_SESSION_ID:-}}"
PROJECTS="$HOME/.claude/projects"
TRANSCRIPT=""
if [ -n "$SESSION" ] && [ -d "$PROJECTS" ]; then
  TRANSCRIPT=$(find "$PROJECTS" -maxdepth 2 -name "$SESSION.jsonl" -type f 2>/dev/null | head -1)
fi
# reported home-relative, since the absolute path names the operator in every artifact it lands in
TRANSCRIPT_SHOWN=${TRANSCRIPT:-none reachable}
TRANSCRIPT_SHOWN=${TRANSCRIPT_SHOWN/#$HOME/$TILDE}

: > "$SCRATCH/live"
FIRED=0
if [ -n "$TRANSCRIPT" ]; then
  LIVE='
  [ .[] | select(.type == "attachment") | .attachment
  | select(.type == "hook_success")
  | { event: (.hookEvent // "?"),
      script: ((.command // "?") | split("/") | last | split(" ") | first) } ]
  | group_by(.event + .script)
  | map({ event: .[0].event, script: .[0].script, runs: length })
  | sort_by(.event, .script)
  | .[] | [ .event, .script, (.runs | tostring) ] | join("")'
  jq -rs "$LIVE" "$TRANSCRIPT" > "$SCRATCH/live" 2>/dev/null || true
  FIRED=$(wc -l < "$SCRATCH/live" | tr -d ' ')
  if [ "$FIRED" -eq 0 ]; then
    warn silent session "the transcript records no hook run at all, which is how a skipped file reads"
  fi
else
  warn no_transcript "${SESSION:-unset}" "liveness is unproven here; registration above still holds"
fi

# ==============
# TELEMETRY
# ==============
ERRORS=$(grep -c '^ERROR|' "$FINDINGS" || true)
WARNINGS=$(grep -c '^WARN|' "$FINDINGS" || true)
ERRORS=${ERRORS:-0}; WARNINGS=${WARNINGS:-0}

KINDS=$(sort "$SCRATCH/kinds" | uniq -c | awk '{ printf "%s%s %s", sep, $1, $2; sep = ", " }')
KINDS=${KINDS:-none}

TODAYS_AUDIT=".construct/operator/hooks/$(date +%Y-%m-%d).md"
if [ -f "$ROOT/$TODAYS_AUDIT" ];
then AUDIT_COUNT=$(grep -c '^## Hooks Audit #' "$ROOT/$TODAYS_AUDIT" || true)
else AUDIT_COUNT=0; fi
AUDIT_COUNT=${AUDIT_COUNT:-0}

if [ "$QUICK" -eq 1 ];
then MODE="quick — report inline, write nothing"; AUDIT_FILE=none
else MODE="audit — append to audit_file"; AUDIT_FILE=$TODAYS_AUDIT; fi

cat <<EOF

=== hooks.sh audit ===
mode: $MODE
audit_file: $AUDIT_FILE
audit_count: $AUDIT_COUNT
next_audit: $((AUDIT_COUNT + 1))
timestamp: $(date '+%Y-%m-%d %H:%M')
version: $(claude --version 2>/dev/null || echo unknown)
session: ${SESSION:-unset}
transcript: $TRANSCRIPT_SHOWN
scopes: $SCOPES file(s) read — $KINDS
groups: $GROUPS_SEEN hook group(s) registered across them
actions: $ACTIONS command path(s) resolved, $ORPHANS orphan(s) under hooks/
blockers: $BLOCKERS action(s) emitting a permissionDecision
errors: $ERRORS
warnings: $WARNINGS
--- what each file registers ---
EOF

if [ ! -s "$SCRATCH/groups" ]; then
  echo "none — no file reachable from here carries a hooks block"
else
  printf '%-34s %-16s %-10s %-14s %s\n' file event matcher kind hooks
  awk -F'\037' '{
    n = split($1, p, "/"); f = p[n]
    m = ($5 == "" ? "(empty)" : $5)
    printf "%-34s %-16s %-10s %-14s %s\n", f, $2, m, $4, $6
  }' "$SCRATCH/groups"
fi

echo "--- what actually fired this session ---"
if [ ! -s "$SCRATCH/live" ]; then
  echo "none — no hook run is recorded, so nothing above is proven live"
else
  printf '%-16s %-32s %s\n' event script runs
  awk -F'\037' '{ printf "%-16s %-32s %s\n", $1, $2, $3 }' "$SCRATCH/live"
fi

echo "--- findings ---"
if [ "$ERRORS" -eq 0 ] && [ "$WARNINGS" -eq 0 ]; then
  echo "none — every scope loads, every matcher is a string, and every action resolves"
else
  sort -t'|' -k1,1 -k2,2 "$FINDINGS" \
    | awk -F'|' '{ printf "%-5s %-14s %-30s %s\n", $1, $2, $3, $4 }'
fi

cat <<'EOF'
--- what this audit cannot tell you ---
- it grades the files this machine can read, so a scope on another machine is never covered
- a matcher this accepts may still be rejected by a newer harness, since the schema is upstream's
- liveness proves a hook ran in THIS session, never that it will run in the next one
- an interactive session dialogs a bad matcher at startup, so only `claude -p` fails in silence
- a hook that runs and exits 0 can still inject nothing; `/operator:context` measures that instead
- nothing here executes a hook, so a blocker's verdict is read from its source, not from a run
============================
EOF

if [ "$ERRORS" -gt 0 ]; then exit 1; fi
if [ "$STRICT" -eq 1 ] && [ "$WARNINGS" -gt 0 ]; then exit 1; fi
exit 0

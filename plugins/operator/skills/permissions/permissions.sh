#!/bin/bash
# ================================================================
# @file permissions.sh - permission floor replay and audit sidecar
# ================================================================
# @description
# PAIR
# - sidecar for `/operator:permissions` — replays `corpus.tsv` against the hooks, then audits rules
# - it answers one question: does the gate actually refuse what the corpus says it must refuse
# - a config can read perfectly and still have a dead hook, which only a replay catches
# - every pretooluse action replays per case, since the harness runs them in parallel and any denies
# - NEVER executes a corpus line; every one is passed to each action as a string and nothing more
# TIERS
# - tier 1 is ground truth, since the hook it feeds is the artifact under test
# - tier 2 is structural fact: drift, dead rules, and which allow rule covers an unnamed command
# - it never models the permission matcher, so it never claims a rule covers anything
# RUN
# - read-only: it replays and reports, and every repair is the user's to apply
# - `--strict` promotes warnings to errors, `--keep` preserves scratch; exits 1 on any error
# - `/operator:settings` wraps this one, so run it directly for the detail rather than the count
# @see plugins/operator/skills/permissions/SKILL.md, plugins/operator/shared/corpus.tsv, plugins/operator/hooks/pretooluse/, plugins/operator/skills/settings/SKILL.md, .claude/settings.json

set -euo pipefail

# the doc is read only after this has already run, so help is refused here or not at all; the doc's
# own '## Help' section owns the output, which is why this prints a marker rather than a usage text
case " $* " in *" --help "*|*" -h "*) echo "help: requested"; exit 0;; esac

# ==============
# PREFLIGHT
# ==============
# the corpus and the hook sit beside this file, not beside the repo being scanned: resolve them
# before anything cds to a repo root, since BASH_SOURCE arrives relative and would follow that cd
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)
CORPUS="$HERE/../../shared/corpus.tsv"
HOOKS="$HERE/../../hooks/pretooluse"
if [ ! -f "$CORPUS" ]; then echo "fatal: no audit/shared/corpus.tsv reachable" >&2; exit 1; fi
if [ ! -d "$HOOKS" ]; then echo "fatal: no plugins/operator/hooks/pretooluse/ reachable" >&2; exit 1; fi

STRICT=0
KEEP=0
for arg in "$@"; do
  case "$arg" in
    --strict) STRICT=1;;
    --keep) KEEP=1;;
    *) echo "fatal: unknown flag $arg" >&2; exit 1;;
  esac
done

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "fatal: not a git repository" >&2; exit 1; fi
cd "$(git rev-parse --show-toplevel)"

# a project's rules can be split across three files, and the audit is meaningless if it reads one
SETTINGS=()
for candidate in .claude/settings.json .claude/settings.local.json "$HOME/.claude/settings.json"; do
  if [ -f "$candidate" ]; then SETTINGS+=("$candidate"); fi
done

# repo-local scratch: the sandbox denies writes outside cwd, and macos mktemp ignores TMPDIR
TMPROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)/tmp"
TMPTAG=$(basename "${BASH_SOURCE[0]}" .sh)
mkdir -p "$TMPROOT"
FINDINGS=$(mktemp "$TMPROOT/$TMPTAG-findings.XXXXXX")
SCRATCH=$(mktemp -d "$TMPROOT/$TMPTAG-scratch.XXXXXX")
# a failed run leaves scratch behind to read; --keep does the same after a clean one
cleanup() { st=$?; if [ "$KEEP" -eq 0 ] && [ "$st" -eq 0 ]; then rm -rf "$FINDINGS" "$SCRATCH"; fi; }
trap cleanup EXIT

err()  { printf 'ERROR|%s|%s|%s\n' "$1" "$2" "$3" >> "$FINDINGS"; }
warn() { printf 'WARN|%s|%s|%s\n' "$1" "$2" "$3" >> "$FINDINGS"; }

# every deny and allow rule across every settings file that exists, one per line
rules_of() {
  local which=$1 file
  for file in "${SETTINGS[@]}"; do
    jq -r --arg w "$which" '.permissions[$w][]? // empty' "$file" 2>/dev/null || true
  done
}
rules_of deny  > "$SCRATCH/deny"
rules_of allow > "$SCRATCH/allow"
rules_of ask   > "$SCRATCH/ask"

# an action answers in json or says nothing at all, and silence from every one is the allow case
# the harness runs the event's actions in parallel and one deny blocks the call; this mirrors that
hook_verdict() {
  local cmd=$1 action out
  for action in "$HOOKS"/*.sh; do
    out=$(jq -n --arg c "$cmd" '{tool_input:{command:$c}}' | bash "$action" 2>/dev/null || true)
    if [ -n "$out" ]; then printf 'deny'; return; fi
  done
  printf 'silent'
}

# two tokens for a tool that takes a subcommand, one token for everything else
base_of() {
  local cmd=$1 first second
  first=$(printf '%s' "$cmd" | awk '{print $1}')
  second=$(printf '%s' "$cmd" | awk '{print $2}')
  case "$first" in
    git|gh|npm|yarn|pnpm|bun|docker|kubectl|aws|terraform|prisma)
      case "$second" in
        -*|"") printf '%s' "$first";;
        *) printf '%s %s' "$first" "$second";;
      esac;;
    *) printf '%s' "$first";;
  esac
}

# ==============
# TIER 1 — ground truth
#   the corpus is replayed into the real hook, so these results are exact rather than modelled
# ==============
T1_PASS=0; T1_FAIL=0
tier1() {
  local effect gate cmd verdict
  while IFS=$'\t' read -r effect gate cmd; do
    case "$effect" in ''|'#'*) continue;; esac
    if [ -z "${cmd:-}" ]; then continue; fi
    # the actions deny or stay silent, and nothing asks any more, so those are the two gates left
    case "$gate" in hook|none) ;; *) continue;; esac
    verdict=$(hook_verdict "$cmd")
    if [ "$gate" = "hook" ]; then
      if [ "$verdict" = "deny" ]; then T1_PASS=$((T1_PASS + 1))
      else T1_FAIL=$((T1_FAIL + 1)); err "$effect" "$cmd" "the hook lets this through; it is meant to block it"; fi
    else
      if [ "$verdict" = "silent" ]; then T1_PASS=$((T1_PASS + 1))
      else T1_FAIL=$((T1_FAIL + 1)); err "$effect" "$cmd" "the hook blocks legitimate work; over-blocking"; fi
    fi
  done < "$CORPUS"
}

# ==============
# TIER 2 — structural fact
#   nothing here predicts the matcher; each check reports what the files literally say
# ==============

# true when a path in the command is denied for the file tools while bash is left free to reach it
tool_scoped() {
  local cmd=$1 token stem head
  read -r -a PARTS <<< "$cmd"
  for token in "${PARTS[@]}"; do
    # every path shape worth checking carries a slash, so one pattern covers ~/x, ./x and /x
    case "$token" in
      */*) ;;
      *) continue;;
    esac
    stem=$(printf '%s' "$token" | sed -E 's#^~/##; s#^\./##; s#^/##')
    head=${stem%%/*}
    if [ -z "$head" ]; then continue; fi
    if grep -E '^(Read|Edit|Write)\(' "$SCRATCH/deny" | grep -qF -- "$head"; then return 0; fi
  done
  return 1
}

# a command no deny rule names, sitting under an allow wildcard, is auto-approved with no prompt
check_named() {
  local effect gate cmd base T2=0
  while IFS=$'\t' read -r effect gate cmd; do
    case "$effect" in ''|'#'*) continue;; esac
    if [ "$gate" != "deny" ]; then continue; fi
    base=$(base_of "$cmd")
    if grep -qF -- "$base" "$SCRATCH/deny"; then continue; fi
    # the path may be denied for Read, Edit and Write while bash still reaches it: the `cp` gap
    if tool_scoped "$cmd"; then
      err "$effect" "$cmd" "path denied for Read/Edit/Write only; bash reaches it via '$base'"
      T2=$((T2 + 1))
      continue
    fi
    # no deny rule names it, so the only question left is whether something allows it outright
    if grep -qE "^Bash\($(printf '%s' "$base" | awk '{print $1}') \*\)$" "$SCRATCH/allow"; then
      err "$effect" "$cmd" "no deny rule names '$base', and an allow wildcard covers it: auto-approved"
    else
      warn "$effect" "$cmd" "no deny rule names '$base'; it will prompt rather than be refused"
    fi
    T2=$((T2 + 1))
  done < "$CORPUS"
  return 0
}

# the hook keeps its own copy of the protected paths, and nothing keeps the two lists in step
# the paths live in one action, block-policy-edits.sh, so drift reads that file and no sibling
check_drift() {
  local path
  grep -E '^PROTECTED=' "$HOOKS/block-policy-edits.sh" \
    | sed -E "s/^PROTECTED=[\"']?//; s/[\"']$//; s/\\\$PROTECTED//" \
    | tr '|' '\n' \
    | sed -E 's/\\//g; s/[()^$]//g; s/\[.*\]//g; s#/$##' \
    | grep -E '^[a-zA-Z.]' | sort -u > "$SCRATCH/hookpaths"
  # ask counts as a guard here, exactly as it does in settingsaudit.sh: a tracked path cannot be
  # denied, since the deny reaches the macos sandbox and blocks git's own unlink mid-checkout
  cat "$SCRATCH/deny" "$SCRATCH/ask" 2>/dev/null \
    | grep -E '^(Edit|Write)\(' \
    | sed -E 's/^(Edit|Write)\(//; s/\)$//' \
    | sed -E 's#^\*\*/##; s#/\*\*$##; s#\*##g' | sort -u > "$SCRATCH/guardedpaths"
  while IFS= read -r path; do
    if [ -z "$path" ]; then continue; fi
    # containment runs both ways: a broad `plugins/**` rule guards `plugins/operator/`
    # without naming it, so a plain substring search in one direction reports a guard that exists
    if grep -qF -- "$path" "$SCRATCH/guardedpaths"; then continue; fi
    if awk -v p="$path" 'NF && index(p, $0) { hit = 1 } END { exit !hit }' "$SCRATCH/guardedpaths"; then continue; fi
    warn drift "$path" "the hook guards this path, but no Edit/Write deny or ask rule names it"
  done < "$SCRATCH/hookpaths"
  while IFS= read -r path; do
    if [ -z "$path" ]; then continue; fi
    case "$path" in .env*) path=".env";; esac
    if grep -qF -- "$path" "$SCRATCH/hookpaths"; then continue; fi
    # a settings glob and a hook regex spell one path differently, so compare by containment too
    if awk -v p="$path" 'NF && index(p, $0) { hit = 1 } END { exit !hit }' "$SCRATCH/hookpaths"; then continue; fi
    warn drift "$path" "a deny or ask rule guards this path, but the hook would not stop bash writing it"
  done < "$SCRATCH/guardedpaths"
}

# a rule whose prefix is already covered by another in the same list never matches anything
check_dead() {
  local list name a b stem
  for list in deny allow; do
    while IFS= read -r a; do
      if [ -z "$a" ]; then continue; fi
      stem=${a%\*}
      if [ "$stem" = "$a" ]; then continue; fi
      while IFS= read -r b; do
        if [ -z "$b" ] || [ "$a" = "$b" ]; then continue; fi
        case "$b" in
          "$stem"*) warn dead_rule "$b" "already covered by '$a' in the $list list";;
        esac
      done < "$SCRATCH/$list"
    done < "$SCRATCH/$list"
    name=$list
  done
  printf '%s' "$name" >/dev/null
}

# a settings file that does not parse is a settings file the harness silently ignores
check_parse() {
  local file
  for file in "${SETTINGS[@]}"; do
    if ! jq empty "$file" >/dev/null 2>&1; then
      err parse "$file" "does not parse as json; the harness cannot read these rules"
    fi
  done
}

tier1
check_named
check_drift
check_dead
check_parse

# ==============
# ARTIFACT
#   this skill's own dated artifact, graded here so nothing outside this file decides its shape
#   the shape lives in this skill's SKILL.md and the labels below are what this sidecar emits
# ==============
ARTIFACT_KIND="permissions"
ARTIFACT_SECTIONS=$'state\nfindings\nresolutions\ntelemetry'
ARTIFACT_LABELS='Drift|Remote Exec|Coverage|Replay|Gap'
ARTIFACT_MAX_WIDTH=100

# this sidecar reports "category|scope|detail", so location folds into the scope field. passing
# four arguments to a three-field reporter is what silently dropped every detail before
artifact_err()  { err "$3" "$1:$2" "$4"; }
artifact_warn() { warn "$3" "$1:$2" "$4"; }

# emit "START<TAB>END<TAB>HEADING" per `## ` entry, so a check can scope itself to one entry
artifact_entries() {
  awk '
    /^## / { if (start) print start "\t" NR - 1 "\t" heading; start = NR; heading = substr($0, 4); next }
    END { if (start) print start "\t" NR "\t" heading }
  ' "$1"
}

# emit "LINENO<TAB>TEXT" for one entry's `### <name>` block; any heading closes it, so a malformed
# entry cannot bleed its body into the entry below
artifact_subsection() {
  awk -v s="$2" -v e="$3" -v want="### $4" '
    NR < s || NR > e { next }
    $0 == want { inside = 1; next }
    /^##+ / { inside = 0 }
    inside { print NR "\t" $0 }
  ' "$1"
}

check_artifact_file() {
  local rel=$1 file=$2
  local base date start end heading number stamp label actual body fenced
  local expected=1 previous='' count=0 found=0 fixed=0 lineno text infence=0
  base=$(basename "$rel" .md)
  date=$(printf '%s' "$base" | cut -c1-10)

  # "one file per day" — the date keeps it append-only and diffable against yesterday
  if ! printf '%s' "$base.md" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}\.md$'; then
    artifact_err "$rel" 1 filename "one file per day, named YYYY-MM-DD.md under its kind"
  fi

  # the agent opens the file with its own path as the h1, so a mismatch means it was copied
  if [ "$(sed -n '1p' "$file")" != "# $rel" ]; then
    artifact_err "$rel" 1 header "line 1 must read '# $rel'"
  fi

  # a fence left unclosed swallows every entry after it, so count before reading any section
  fenced=$(grep -cE '^[[:space:]]*```' "$file" || true)
  if [ $((fenced % 2)) -ne 0 ]; then
    artifact_err "$rel" 1 fences "$fenced fence markers; one is unclosed"
  fi

  # scaffolding left in a shipped file reads as fact to everyone downstream
  while IFS= read -r text; do
    [ -n "$text" ] || continue
    artifact_err "$rel" "${text%%:*}" placeholder "template scaffolding survived: $(printf '%s' "${text#*:}" \
      | grep -oE 'YYYY-MM-DD|HH:MM|\*example:\*|repeat the above format' | head -n 1)"
  done < <(grep -nE 'YYYY-MM-DD|HH:MM|\*example:\*|repeat the above format' "$file" || true)

  # "lines carry a single clause, capped at 100" — telemetry is pasted by contract, so it is exempt
  lineno=0
  while IFS= read -r text; do
    lineno=$((lineno + 1))
    case "$text" in '```'*) infence=$((1 - infence)); continue;; esac
    [ "$infence" -eq 1 ] && continue
    if [ ${#text} -gt "$ARTIFACT_MAX_WIDTH" ]; then
      artifact_err "$rel" "$lineno" width "${#text} chars; the cap is $ARTIFACT_MAX_WIDTH"
    fi
  done < "$file"

  while IFS=$'\t' read -r start end heading; do
    count=$((count + 1))
    # "appended each run" — numbering and timestamps are the append order, and the kind pairs the
    # heading to the file, so a settings entry in the git file is caught rather than merged
    if ! printf '%s' "$heading" \
      | grep -qE '^[A-Z][A-Za-z]* Audit #[0-9]+: [0-9]{4}-[0-9]{2}-[0-9]{2} ([01][0-9]|2[0-3]):[0-5][0-9]$'
    then
      artifact_err "$rel" "$start" entry_heading "entries read '## <Kind> Audit #N: YYYY-MM-DD HH:MM'"
      continue
    fi
    number=$(printf '%s' "$heading" | sed -n 's/^[A-Za-z]\{1,\} Audit #\([0-9]\{1,\}\):.*/\1/p')
    stamp=$(printf '%s' "$heading" | sed -n 's/^[A-Za-z]\{1,\} Audit #[0-9]\{1,\}: \(.*\)$/\1/p')
    label=$(printf '%s' "$heading" | sed -n 's/^\([A-Za-z]\{1,\}\) Audit #.*/\1/p' | tr '[:upper:]' '[:lower:]')
    if [ "$label" != "$ARTIFACT_KIND" ]; then
      artifact_err "$rel" "$start" entry_kind "a $label entry in the file for $ARTIFACT_KIND"
    fi
    if [ "$number" -ne "$expected" ]; then
      artifact_err "$rel" "$start" entry_numbering "entry $number where $expected was expected"
    fi
    expected=$((number + 1))
    case "$stamp" in
      "$date "*) ;;
      *) artifact_err "$rel" "$start" entry_date "timestamped $stamp in the file for $date";;
    esac
    if [ -n "$previous" ] && [[ "$stamp" < "$previous" ]]; then
      artifact_warn "$rel" "$start" entry_order "timestamp precedes the entry above it; runs append"
    fi
    previous=$stamp

    actual=$(awk -v s="$start" -v e="$end" 'NR >= s && NR <= e && /^### / { print substr($0, 5) }' "$file")
    if [ "$actual" != "$ARTIFACT_SECTIONS" ]; then
      artifact_err "$rel" "$start" section_order "got $(printf '%s' "$actual" | tr '\n' '>' | sed 's/>$//')"
    fi

    found=0
    while IFS=$'\t' read -r lineno text; do
      printf '%s' "$text" | grep -qE '^- ' || continue
      found=$((found + 1))
      if ! printf '%s' "$text" | grep -qE '^- \*\*[^*]+\*\* — .'; then
        artifact_err "$rel" "$lineno" finding_shape 'findings read "- **Label** — what is wrong, and on what"'
        continue
      fi
      label=$(printf '%s' "$text" | sed -n 's/^- \*\*\([^*]*\)\*\*.*/\1/p')
      if ! printf '%s' "$label" | grep -qE "^($ARTIFACT_LABELS)\$"; then
        artifact_warn "$rel" "$lineno" finding_label "'$label' is not a label this sidecar emits"
      fi
    done < <(artifact_subsection "$file" "$start" "$end" findings)
    if [ "$found" -eq 0 ]; then
      artifact_warn "$rel" "$start" no_findings "no findings listed; a clean run says so in one line"
    fi

    fixed=0
    while IFS=$'\t' read -r lineno text; do
      printf '%s' "$text" | grep -qE '^- \[[ x]\] ' || continue
      fixed=$((fixed + 1))
      if ! printf '%s' "$text" | grep -qE '`|/[a-z]+:'; then
        artifact_warn "$rel" "$lineno" resolution_shape "name a command or a slash command, not prose"
      fi
    done < <(artifact_subsection "$file" "$start" "$end" resolutions)
    if [ "$found" -ne "$fixed" ]; then
      artifact_err "$rel" "$start" resolution_parity "$found finding(s), $fixed resolution(s); one each"
    fi

    body=$(artifact_subsection "$file" "$start" "$end" telemetry | cut -f2- | grep -v '^[[:space:]]*$' || true)
    if [ -z "$body" ]; then
      artifact_err "$rel" "$start" telemetry "telemetry holds the raw sidecar output, never blank"
    elif [ "$(printf '%s' "$body" | grep -c '^```' || true)" -lt 2 ]; then
      artifact_warn "$rel" "$start" telemetry "fence the raw output, so a reader can tell it from prose"
    fi
  done < <(artifact_entries "$file")

  if [ "$count" -eq 0 ]; then
    artifact_warn "$rel" 1 empty "seeded, holds no entries yet"
  fi
}

# grade every file of this kind, not only the one today's run appends to: an older defect stays a
# defect, and nothing else reads these files
check_artifact() {
  local dir=$1 found resolved
  dir=${dir%/}
  case "$dir" in *.md) dir=$(dirname "$dir");; esac
  resolved=$dir
  if [ ! -d "$resolved" ] && [ -n "${ROOT:-}" ] && [ -d "$ROOT/$dir" ]; then resolved="$ROOT/$dir"; fi
  [ -d "$resolved" ] || return 0
  for found in "$resolved"/*.md; do
    [ -f "$found" ] || continue
    check_artifact_file "${found#"${ROOT:-}"/}" "$found"
  done
}

check_artifact ".construct/operator/permissions"

# ==============
# TELEMETRY
# ==============
ERRORS=$(grep -c '^ERROR|' "$FINDINGS" || true)
WARNINGS=$(grep -c '^WARN|' "$FINDINGS" || true)
CASES=$(grep -cvE '^#|^$' "$CORPUS" || true)

# audit: one file per day per kind, so two triggers on the same day never interleave one file
# reported, never created: the sidecar names the path and the count, the agent writes the entry
AUDIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
TODAYS_AUDIT=".construct/operator/permissions/$(date +%Y-%m-%d).md"
if [ -f "$AUDIT_ROOT/$TODAYS_AUDIT" ];
then AUDIT_COUNT=$(grep -c '^## Permissions Audit #' "$AUDIT_ROOT/$TODAYS_AUDIT" || true)
else AUDIT_COUNT=0; fi
AUDIT_COUNT=${AUDIT_COUNT:-0}

# the ledger `suggest-allow-rules` appends to: one json line per command shape documented to prompt
# it is the only view of over-asking either layer has, since a prompt is the harness's to decide
LEDGER="$AUDIT_ROOT/.construct/operator/permissions/asked.jsonl"
SUGGESTED=0
if [ -s "$LEDGER" ]; then
  SUGGESTED=$(jq -rs 'group_by(.rule) | length' "$LEDGER" 2>/dev/null || echo 0)
fi
SUGGESTED=${SUGGESTED:-0}

cat <<EOF

=== permissions.sh audit ===
audit_file: $TODAYS_AUDIT
audit_count: $AUDIT_COUNT
next_audit: $((AUDIT_COUNT + 1))
timestamp: $(date '+%Y-%m-%d %H:%M')
corpus: $CORPUS
settings: ${SETTINGS[*]:-none found}
hooks: $HOOKS
cases: $CASES
tier1 replayed: $((T1_PASS + T1_FAIL)) — $T1_PASS held, $T1_FAIL failed
errors: $ERRORS
warnings: $WARNINGS
suggested: $SUGGESTED
--- findings ---
EOF

if [ "$ERRORS" -eq 0 ] && [ "$WARNINGS" -eq 0 ]; then
  echo "none — every replayed case held, and the settings files agree with the hook"
else
  sort -t'|' -k1,1 -k2,2 "$FINDINGS" \
    | awk -F'|' '{ printf "%-5s %-22s %-46s %s\n", $1, $2, substr($3, 1, 44), $4 }'
fi

echo "--- allow rules to add next ---"
if [ "$SUGGESTED" -eq 0 ]; then
  echo "none — no command has tripped suggest-allow-rules since the ledger was last cleared"
else
  # ranked by how often the shape asked, since the one that costs the most turns is the one to paste
  RANK='group_by(.rule)'
  RANK="$RANK"' | map({rule: .[0].rule, reason: .[0].reason, hits: length, last: (map(.ts)|max)})'
  RANK="$RANK"' | sort_by(-.hits, .rule)[] | [(.hits|tostring), .last, .rule, .reason] | @tsv'
  jq -rs "$RANK" "$LEDGER" 2>/dev/null \
    | awk -F'\t' '{ printf "%-5s %-21s %s\n      %s\n", $1 "x", $2, $3, $4 }'
  echo "  paste each rule into \"allow\" in .claude/settings.json, then clear ${LEDGER#"$AUDIT_ROOT"/}"
fi

cat <<'EOF'
--- what this audit cannot tell you ---
- it never models the permission matcher, so "no deny rule names it" is not "it is allowed"
- a rule may still fail to match for a reason only the harness knows; test the ones that matter
- neither layer sees inside plugins/*/*.sh, so an allow-listed script bypasses both by design
- the hook matches command strings, not intent, so it over-blocks a string that merely names a path
- settings load at session start, so an edited file changes nothing until the session restarts
- the ledger carries only the shapes the hook knows, so a prompt for any other reason never lands
- a corpus is only as good as its spellings; add one every time a new bypass turns up
============================
EOF

if [ "$ERRORS" -gt 0 ]; then exit 1; fi
if [ "$STRICT" -eq 1 ] && [ "$WARNINGS" -gt 0 ]; then exit 1; fi
exit 0


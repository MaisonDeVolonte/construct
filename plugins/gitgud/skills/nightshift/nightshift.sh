#!/bin/bash
# ==========================================================================
# @file nightshift.sh - plan scanner and issue writer for a cloud coding agent
# ==========================================================================
# @description
# PAIR
# - sidecar for `/gitgud:nightshift` - scans every plan, then writes each issue to github
# - the trigger grades ease, plans the batch, and gates twice; this file never decides which lines
# - rides plain curl end to end, since gh cannot verify tls inside the sandbox (#26466)
# SCAN
# - a bare run reads plans from .construct/retardify/plan/*.md and prints the candidates
# - a plan holding '<n>. CLOSED' is a record, and 'Deferred Work' is a wishlist, so neither is read
# - only the lowest numbered stage holding a live line is read, since a cloud agent sees main
# - free text is the user's guidance, echoed rather than acted on, since only the model plans
# TESTS
# - open: '- [ ] ' and not struck; agentic: no 'HUMAN:' label; filed: no marker, no open issue
# - path: a token holding '/' or '.' resolves at HEAD, or sits in a tracked directory
# - ease is not a test here: sizing a line and writing its done condition is the trigger's call
# SUBCOMMANDS
# - probe <body-file> grades one prepared issue body against the same tests and prints a verdict
# - issue <title> <body-file> <yes|no> probes again, then creates the issue, assigned or not
# - mark <plan:line> <n> appends the issue number to that plan line, after one snapshot a day
# - each exits before the scan, since the drain calls back in mid-run
# ASSIGN
# - assigning adds copilot-swe-agent[bot] and an agent_assignment to the same issues call
# - it is refused unless 'copilot:' reads assignable, which is a graphql suggestedActors probe
# AUTH
# - GH_TOKEN_OPERATOR rides along when set, masked or real, since the proxy injects on its hosts
# - a rejected token falls back to anonymous with a warning, and the value is never printed
# @see plugins/gitgud/skills/nightshift/SKILL.md, plugins/gitgud/shared/secrets.sh, plugins/gitgud/shared/handover.sh, plugins/gitgud/skills/deliver/deliver.sh, plugins/gitgud/skills/issues/issues.sh

set -euo pipefail

# the doc is read only after this has already run, so help is refused here or not at all; the doc's
# own '## Help' section owns the output, which is why this prints a marker rather than a usage text
case " $* " in *" --help "*|*" -h "*) echo "help: requested"; exit 0;; esac

# the smoke case proves this file parses and its guards return; /test-skills reads the sources,
# the @see paths and the tool guards statically, so nothing here runs a step of the skill
case " $* " in *" --test "*) echo "test: ok"; exit 0;; esac

die() { echo "fatal: $*" >&2; exit 1; }

SUB=${1:-}

# ==============
# PREFLIGHT
# ==============
# the shared files resolve from this file before any cd, since a marketplace cwd has no plugins/
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)
SHARED=$(cd "$HERE/../../shared" 2>/dev/null && pwd || true)
for NEED in secrets.sh handover.sh; do
  [ -f "$SHARED/$NEED" ] || die "no shared/$NEED reachable from this sidecar"
done
# shellcheck source=../../shared/secrets.sh
. "$SHARED/secrets.sh"
# shellcheck source=../../shared/handover.sh
. "$SHARED/handover.sh"

require_tools jq curl git awk
require_repo
ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"

# the slug comes from origin, so an issue lands on the repo whose plan named the line
ORIGIN=$(git remote get-url origin 2>/dev/null || true)
[ -n "$ORIGIN" ] || die "this repo has no origin remote, so there is nowhere to file an issue"
SLUG=$(printf '%s' "$ORIGIN" \
  | sed -e 's|^git@github\.com:||' -e 's|^ssh://git@github\.com/||' \
        -e 's|^https://github\.com/||' -e 's|^git://github\.com/||' -e 's|\.git$||')
case "$SLUG" in
  */*) : ;;
  *) die "origin is not a github repo: $ORIGIN";;
esac

API="https://api.github.com"
PLAN_DIR=".construct/retardify/plan"
SNAP_DIR=".construct/gitgud/nightshift/plans"
LABEL="copilot"
BOT="copilot-swe-agent"
GQL_FEATURES="issues_copilot_assignment_api_support,coding_agent_model_selection"
PRINT_MAX=24
NOTE_CHARS=360

TMP=$(mktemp -d "${TMPDIR:-/tmp}/gitgud-nightshift.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
BODY="$TMP/body.json"
FINDINGS="$TMP/findings.txt"
: > "$FINDINGS"

WARNINGS=0

# the shared secret scan reports through these two, so each body gets its own findings file
err()  { printf 'ERROR|%s|%s|%s|%s\n' "$1" "$2" "$3" "$4" >> "$FINDINGS"; }
warn() { printf 'WARN|%s|%s|%s|%s\n' "$1" "$2" "$3" "$4" >> "$FINDINGS"; }

# \001 as the sed delimiter, since the secret patterns themselves carry /, | and @
SEP=$(printf '\001')
redact() {
  LC_ALL=C sed -E "s${SEP}${SECRET_PATTERNS}${SEP}[redacted]${SEP}g"
}

# ==============
# AUTH
# ==============
# the masked value is sent as-is, since the sandbox proxy swaps it on its inject hosts
AUTH_HEADER=""
AUTH_MODE="anonymous"
GH_AUTH=${GH_TOKEN_OPERATOR:-}
[ -z "$GH_AUTH" ] && GH_AUTH=${GITHUB_TOKEN:-}
if [ -n "$GH_AUTH" ]; then
  PROBE=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 20 \
    -H "Authorization: Bearer $GH_AUTH" "$API/rate_limit" 2>/dev/null || echo 000)
  if [ "$PROBE" = 200 ]; then
    AUTH_HEADER="Authorization: Bearer $GH_AUTH"; AUTH_MODE="token"
  else
    AUTH_MODE="anonymous (token rejected: http $PROBE)"; WARNINGS=$((WARNINGS+1))
  fi
fi

# fetches never abort the run: gh_api echoes the http code and the caller decides what it means
gh_api() {
  curl -sS -o "$BODY" -w '%{http_code}' --max-time 20 \
    -H "Accept: application/vnd.github+json" \
    ${AUTH_HEADER:+-H "$AUTH_HEADER"} "$1" 2>/dev/null || echo 000
}

# a write posts a json file and echoes the http code, so the caller reads the response in BODY
post_json() {
  curl -sS -o "$BODY" -w '%{http_code}' --max-time 30 -X POST \
    -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" \
    -H "$AUTH_HEADER" -H "Content-Type: application/json" -d "@$2" "$1" 2>/dev/null || echo 000
}

# ==============
# REMOTE STATE
# ==============
# the label is advisory: a missing one is created with the first issue, and an unreadable one warns
LABEL_CODE=$(gh_api "$API/repos/$SLUG/labels/$LABEL")
case "$LABEL_CODE" in
  200) LABEL_STATE=present;;
  404) LABEL_STATE=missing;;
  *)   LABEL_STATE="unknown (http $LABEL_CODE)"; WARNINGS=$((WARNINGS+1));;
esac

# open copilot issues hold the filed lines, so a failed fetch reads 'unavailable' and blocks filing
ISSUE_BODIES="$TMP/issue-bodies.txt"
: > "$ISSUE_BODIES"
OPEN_COPILOT=0
DEDUP=ok
CODE=$(gh_api "$API/repos/$SLUG/issues?state=open&labels=$LABEL&per_page=100")
if [ "$CODE" = 200 ]; then
  OPEN_COPILOT=$(jq '[.[] | select(.pull_request == null)] | length' "$BODY")
  jq -r '.[] | select(.pull_request == null) | (.body // "")' "$BODY" >> "$ISSUE_BODIES"
else
  DEDUP="unavailable (http $CODE)"; WARNINGS=$((WARNINGS+1))
fi

# can copilot be assigned here: only a token can ask, since graphql refuses anonymous calls
COPILOT_STATE="unknown (no token)"
if [ -n "$AUTH_HEADER" ]; then
  GQL='query($o:String!,$n:String!){repository(owner:$o,name:$n){suggestedActors(capabilities:[CAN_BE_ASSIGNED],first:100){nodes{login}}}}'
  PAYLOAD=$(jq -n --arg q "$GQL" --arg o "${SLUG%%/*}" --arg n "${SLUG#*/}" \
    '{query: $q, variables: {o: $o, n: $n}}')
  GQL_CODE=$(curl -sS -o "$BODY" -w '%{http_code}' --max-time 20 \
    -H "$AUTH_HEADER" -H "GraphQL-Features: $GQL_FEATURES" \
    -d "$PAYLOAD" "$API/graphql" 2>/dev/null || echo 000)
  if [ "$GQL_CODE" = 200 ] && jq -e '.data.repository.suggestedActors.nodes' "$BODY" >/dev/null 2>&1; then
    if jq -e --arg bot "$BOT" '[.data.repository.suggestedActors.nodes[].login] | index($bot)' "$BODY" >/dev/null 2>&1; then
      COPILOT_STATE=assignable
    else
      COPILOT_STATE="not assignable ($BOT is not a suggested actor)"
    fi
  else
    COPILOT_STATE="unknown (graphql http $GQL_CODE)"; WARNINGS=$((WARNINGS+1))
  fi
fi

# ==============
# TREE
# ==============
# the path test reads HEAD rather than the worktree, because a cloud agent only ever sees main
HEAD_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)
HEAD_SHA=$(git rev-parse --short HEAD 2>/dev/null || echo unknown)
MAIN_BRANCH=$(cfg .github.main_branch main)
TREE="$TMP/tree.txt"
DIRS="$TMP/dirs.txt"
git ls-tree -r --name-only HEAD > "$TREE"
awk '{ while (sub(/\/[^\/]*$/, "")) print }' "$TREE" | sort -u > "$DIRS"
if [ "$HEAD_BRANCH" != "$MAIN_BRANCH" ]; then WARNINGS=$((WARNINGS+1)); fi

# prints file, dir, new or none; a path to be created counts as new when its parent is tracked
resolve_path() {
  local tok=$1 parent
  if grep -Fxq -- "$tok" "$TREE"; then echo file; return; fi
  if grep -Fxq -- "$tok" "$DIRS"; then echo dir; return; fi
  case "$tok" in
    */*)
      parent=${tok%/*}
      if grep -Fxq -- "$parent" "$DIRS"; then echo new; return; fi;;
    *)
      # a bare file name matches wherever it sits in the tree
      if awk -v t="/$tok" 'length($0) > length(t) && substr($0, length($0) - length(t) + 1) == t { f = 1; exit } END { exit !f }' "$TREE"; then
        echo file; return; fi;;
  esac
  echo none
}

# a bare name can match several files, so the paths it hits are listed for the trigger
bare_hits() {
  local tok=$1 hits n
  hits=$(awk -v t="/$tok" 'length($0) > length(t) && substr($0, length($0) - length(t) + 1) == t' "$TREE")
  if grep -Fxq -- "$tok" "$TREE"; then hits="$tok"$'\n'"$hits"; fi
  hits=$(printf '%s\n' "$hits" | sed '/^$/d')
  n=$(printf '%s\n' "$hits" | grep -c . || true)
  if [ "$n" -le 3 ]; then printf '%s' "$hits" | paste -sd ';' - | sed 's/;/, /g'; else printf '%s matches' "$n"; fi
}

# file names plain text may carry without backticks, as older plans wrote 'audit.sh:39'
BARE_EXT='sh|md|json|ts|tsx|js|jsx|mjs|yml|yaml|php|css|toml|txt'

# every token that reads like a path, deduplicated; commands and globs never match
path_tokens() {
  { printf '%s\n' "$1" | { grep -o '`[^`]*`' || true; } | tr -d '`'
    printf '%s\n' "$1" | { grep -owE "[A-Za-z0-9_@./-]+\.($BARE_EXT)(:[0-9]+(-[0-9]+)?)?" || true; }
  } | sed -E 's/:[0-9]+(-[0-9]+)?$//; s|^\./||; s|/$||' \
    | { grep -E '^[A-Za-z0-9_.@/-]+$' || true; } | { grep -E '[/.]' || true; } \
    | { grep -vE '^-|^[0-9v.]+$' || true; } | awk '!seen[$0]++'
}

# the text of numbered note $2 in plan $1, folded to one line
note_text() {
  awk -v n="$2" '
    /^## Notes/ { inNotes = 1; next }
    !inNotes { next }
    match($0, /^[0-9]+\. /) {
      if (on) exit
      if (substr($0, 1, RLENGTH - 2) == n) { on = 1; sub(/^[0-9]+\. /, ""); out = $0 }
      next
    }
    on && /^ +[^ ]/ { sub(/^ +/, ""); out = out " " $0; next }
    on { exit }
    END { print out }' "$1"
}

# the item opening at line $2 of plan $1, printed as END then TAB then its joined text
item_span() {
  awk -v start="$2" '
    NR == start { txt = substr($0, 7); end = NR; on = 1; next }
    on && /^ +[^ -]/ { l = $0; sub(/^ +/, "", l); txt = txt " " l; end = NR; next }
    on { exit }
    END { printf "%d\t%s\n", end, txt }' "$1"
}

# ==============
# GATE
# ==============
# one body graded by the scan's tests, so an approved record can still be refused at write time
check_body() {
  local file=$1 part coord path line span text plain tok kind good=""
  [ -s "$file" ] || { echo "the body file is empty or missing"; return; }
  for part in 'Done when:' 'Steps:' 'Gates:' 'Touch nothing else.' 'Source: '; do
    grep -q "^$part" "$file" || { echo "the body has no '$part' part"; return; }
  done
  coord=$(sed -n 's/^Source: //p' "$file" | head -n 1)
  case "$coord" in
    "$PLAN_DIR"/*.md:[0-9]*) ;;
    *) echo "Source is not a plan coordinate under $PLAN_DIR"; return;;
  esac
  path=${coord%:*}
  line=${coord##*:}
  case "$path" in *..*) echo "Source holds a parent path"; return;; esac
  [ -f "$path" ] || { echo "the plan is gone: $path"; return; }
  case "$(sed -n "${line}p" "$path")" in
    "- [ ] "*) ;;
    *) echo "plan line $line is no longer an open checklist item"; return;;
  esac
  span=$(item_span "$path" "$line")
  text=${span#*$'\t'}
  case "$text" in HUMAN:*) echo "the plan line is labelled HUMAN"; return;; esac
  if printf '%s' "$text" | grep -qE ' \(#[0-9]+\)$'; then echo "the plan line already carries an issue number"; return; fi
  plain=$text
  if [ "$DEDUP" != ok ]; then echo "dedup is $DEDUP, so a double filing cannot be ruled out"; return; fi
  if grep -Fq -- "$plain" "$ISSUE_BODIES" || grep -Fq -- "Source: $coord" "$ISSUE_BODIES"; then
    echo "an open $LABEL issue already holds this line"; return; fi
  : > "$FINDINGS"
  scan_secrets "$file" || true
  if grep -q '^ERROR|' "$FINDINGS"; then echo "the body holds a credential-shaped string"; return; fi
  while IFS= read -r tok; do
    [ -n "$tok" ] || continue
    kind=$(resolve_path "$tok")
    if [ "$kind" != none ]; then good=yes; fi
  done < <(path_tokens "$(grep -v '^Source: ' "$file")")
  [ -n "$good" ] || echo "no path in the body resolves at HEAD"
}

cmd_probe() {
  local file=${1:-} reason
  [ -n "$file" ] || die "probe takes a body file"
  reason=$(check_body "$file")
  if [ -z "$reason" ]; then echo "verdict: ok"; else echo "verdict: deny"; echo "reason: $reason"; fi
}

# one issue per call, so the drain can stop on the first refusal and nothing after it is written
cmd_issue() {
  local title=${1:-} file=${2:-} assign=${3:-} reason payload code n url who
  [ -n "$title" ] && [ -f "$file" ] || die "issue takes a title, a body file, and yes or no"
  case "$assign" in yes|no) ;; *) die "the third argument is yes or no";; esac
  refuse() { echo "issue: refused"; echo "reason: $1"; exit 1; }
  reason=$(check_body "$file")
  [ -z "$reason" ] || refuse "$reason"
  [ -n "$AUTH_HEADER" ] || refuse "filing needs a token, and auth is $AUTH_MODE"
  if [ "$assign" = yes ] && [ "$COPILOT_STATE" != assignable ]; then
    refuse "assign needs copilot assignable, and it reads: $COPILOT_STATE"; fi

  if [ "$LABEL_STATE" = missing ]; then
    jq -n --arg n "$LABEL" '{name: $n, color: "5319e7", description: "scoped for a cloud coding agent"}' > "$TMP/label.json"
    code=$(post_json "$API/repos/$SLUG/labels" "$TMP/label.json")
    case "$code" in 201|422) ;; *) refuse "the label could not be created (http $code)";; esac
  fi

  payload="$TMP/issue.json"
  if [ "$assign" = yes ]; then
    jq -n --arg t "$title" --rawfile b "$file" --arg l "$LABEL" --arg bot "${BOT}[bot]" \
      --arg repo "$SLUG" --arg base "$MAIN_BRANCH" \
      '{title: $t, body: $b, labels: [$l], assignees: [$bot],
        agent_assignment: {target_repo: $repo, base_branch: $base, custom_instructions: "", custom_agent: "", model: ""}}' > "$payload"
  else
    jq -n --arg t "$title" --rawfile b "$file" --arg l "$LABEL" '{title: $t, body: $b, labels: [$l]}' > "$payload"
  fi
  code=$(post_json "$API/repos/$SLUG/issues" "$payload")
  if [ "$code" != 201 ]; then
    echo "issue: failed"; echo "http: $code"
    echo "reason: $(jq -r '.message // "no message"' "$BODY" 2>/dev/null)"
    exit 1
  fi
  n=$(jq -r '.number' "$BODY")
  url=$(jq -r '.html_url' "$BODY")
  who=$(jq -r '[.assignees[].login] | join(",") | if . == "" then "none" else . end' "$BODY")
  echo "issue: #$n"
  echo "url: $url"
  echo "assignees: $who"
}

# a filed plan line wears its issue number, after one plan snapshot a day
cmd_mark() {
  local coord=${1:-} n=${2:-} path line span end text endtext marker snap
  case "$n" in ''|*[!0-9]*) die "mark takes an issue number";; esac
  case "$coord" in
    "$PLAN_DIR"/*.md:[0-9]*) ;;
    *) die "mark takes a plan coordinate under $PLAN_DIR";;
  esac
  path=${coord%:*}
  line=${coord##*:}
  case "$path" in *..*) die "mark takes no parent path";; esac
  [ -f "$path" ] || die "no such plan: $path"
  case "$(sed -n "${line}p" "$path")" in
    "- [ ] "*) ;;
    *) echo "mark: skipped (line $line is not an open item)"; return;;
  esac
  span=$(item_span "$path" "$line")
  end=${span%%$'\t'*}
  text=${span#*$'\t'}
  if printf '%s' "$text" | grep -qE ' \(#[0-9]+\)$'; then echo "mark: skipped (already marked)"; return; fi
  endtext=$(sed -n "${end}p" "$path")
  marker=" (#$n)"
  if [ $(( ${#endtext} + ${#marker} )) -gt 100 ]; then
    echo "mark: skipped (line $end would pass 100 characters)"; return; fi
  mkdir -p "$SNAP_DIR"
  snap="$SNAP_DIR/$(date +%F)-$(basename "$path")"
  [ -f "$snap" ] || cp "$path" "$snap"
  awk -v e="$end" -v m="$marker" 'NR == e { print $0 m; next } { print }' "$path" > "$TMP/plan.new"
  cat "$TMP/plan.new" > "$path"
  echo "mark: ok $coord #$n"
  echo "snapshot: $snap"
}

# a subcommand is the drain calling back in mid-run, so it writes and exits before the scan below
case "$SUB" in
  probe)  shift; cmd_probe "$@"; exit 0;;
  issue)  shift; cmd_issue "$@"; exit 0;;
  mark)   shift; cmd_mark "$@"; exit 0;;
esac

# free text is the user's guidance, echoed rather than acted on, since only the model plans
GUIDANCE=${*:-}
GUIDANCE=${GUIDANCE//\"/}

# ==============
# SCAN
# ==============
# one awk pass per plan lists every unticked checklist line with its stage, so bash only judges
rows_of() {
  awk '
    function flush() { if (have) { printf "%d\t%s\t%s\n", ln, st, txt; have = 0 } }
    /^## / { flush(); sec = $0; next }
    sec != "## Checklist" { next }
    /^### / {
      flush()
      if (match($0, /^### [0-9]+\. /)) stage = substr($0, 5, RLENGTH - 6); else stage = "deferred"
      next
    }
    /^- \[ \] / { flush(); have = 1; ln = NR; st = stage; txt = substr($0, 7); next }
    have && /^ +[^ -]/ { sub(/^ +/, ""); txt = txt " " $0; next }
    { flush() }
    END { flush() }' "$1"
}

PLANS_TOTAL=0; PLANS_CLOSED=0; PLANS_IDLE=0; PLANS_READ=0
LIVE=0; STRUCK=0; DEFERRED=0; HELD=0; WINDOW=0
SK_AGENTIC=0; SK_FILED=0; SK_PATH=0; SK_SECRET=0
CANDS=0; PRINTED=0; SCRUB=0
: > "$TMP/cands.txt"
: > "$TMP/skips.txt"

while IFS= read -r PLAN; do
  [ -n "$PLAN" ] || continue
  PLANS_TOTAL=$((PLANS_TOTAL+1))
  if grep -qE '^[0-9]+\. CLOSED ' "$PLAN"; then PLANS_CLOSED=$((PLANS_CLOSED+1)); continue; fi
  NAME=$(basename "$PLAN")
  ROWS=$(rows_of "$PLAN")
  STRUCK=$((STRUCK + $(printf '%s\n' "$ROWS" | grep -c $'\t~~' || true)))
  DEFERRED=$((DEFERRED + $(printf '%s\n' "$ROWS" | awk -F'\t' '$2 == "deferred" && $3 !~ /^~~/' | wc -l | tr -d ' ')))
  # the lowest stage with a live line gates every later stage, HUMAN lines included
  LOW=$(printf '%s\n' "$ROWS" | awk -F'\t' '$2 ~ /^[0-9]+$/ && $3 !~ /^~~/ { if (m == "" || $2 + 0 < m) m = $2 + 0 } END { print m }')
  if [ -z "$LOW" ]; then PLANS_IDLE=$((PLANS_IDLE+1)); continue; fi
  PLANS_READ=$((PLANS_READ+1))
  LIVE=$((LIVE + $(printf '%s\n' "$ROWS" | awk -F'\t' '$2 ~ /^[0-9]+$/ && $3 !~ /^~~/' | wc -l | tr -d ' ')))
  HELD=$((HELD + $(printf '%s\n' "$ROWS" | awk -F'\t' -v low="$LOW" '$2 ~ /^[0-9]+$/ && $2 + 0 > low + 0 && $3 !~ /^~~/' | wc -l | tr -d ' ')))

  while IFS=$'\t' read -r LN STAGE TEXT; do
    [ "$STAGE" = "$LOW" ] || continue
    case "$TEXT" in '~~'*) continue;; esac
    WINDOW=$((WINDOW+1))
    SHORT=$(printf '%s' "$TEXT" | cut -c1-70)

    case "$TEXT" in
      HUMAN:*) SK_AGENTIC=$((SK_AGENTIC+1)); printf 'agentic | %s:%s | %s\n' "$NAME" "$LN" "$SHORT" >> "$TMP/skips.txt"; continue;;
    esac

    # a marker means filed, and so does the line text sitting inside an open copilot issue
    PLAIN=$(printf '%s' "$TEXT" | sed -E 's/ \(#[0-9]+\)$//')
    FILED=no
    if printf '%s' "$TEXT" | grep -qE ' \(#[0-9]+\)$'; then FILED=yes; fi
    if grep -Fq -- "$PLAIN" "$ISSUE_BODIES" 2>/dev/null || grep -Fq -- "Source: $PLAN:$LN" "$ISSUE_BODIES" 2>/dev/null; then FILED=yes; fi
    if [ "$FILED" = yes ]; then SK_FILED=$((SK_FILED+1)); printf 'filed | %s:%s | %s\n' "$NAME" "$LN" "$SHORT" >> "$TMP/skips.txt"; continue; fi

    # one resolving token is enough, and the unresolved rest are listed for the trigger to weigh
    GOOD=""; BAD=""
    while IFS= read -r TOK; do
      [ -n "$TOK" ] || continue
      KIND=$(resolve_path "$TOK")
      DETAIL=$KIND
      case "$TOK" in */*) ;; *) [ "$KIND" != file ] || DETAIL="file: $(bare_hits "$TOK")";; esac
      if [ "$KIND" = none ]; then BAD="${BAD:+$BAD, }$TOK"; else GOOD="${GOOD:+$GOOD, }$TOK ($DETAIL)"; fi
    done < <(path_tokens "$TEXT")
    if [ -z "$GOOD" ]; then
      SK_PATH=$((SK_PATH+1)); printf 'path | %s:%s | %s\n' "$NAME" "$LN" "$SHORT" >> "$TMP/skips.txt"; continue
    fi

    # notes ride along so the trigger can size the line without opening the plan
    NOTES=""
    REFS=$(printf '%s' "$TEXT" | sed -nE 's/.*\(see (#[0-9, #]+)\).*/\1/p' | { grep -oE '[0-9]+' || true; } | head -n 2)
    for N in $REFS; do
      NOTES="$NOTES
note $N: $(note_text "$PLAN" "$N" | tr -s '[:space:]' ' ' | cut -c1-"$NOTE_CHARS")"
    done

    # the secret scan reads the exact text that would leave the laptop
    CAND_FILE="$TMP/cand.txt"
    printf '%s\n%s\n' "$TEXT" "$NOTES" > "$CAND_FILE"
    : > "$FINDINGS"
    scan_secrets "$CAND_FILE" || true
    if grep -q '^ERROR|' "$FINDINGS"; then
      SK_SECRET=$((SK_SECRET+1)); printf 'secret | %s:%s | a credential-shaped string; text withheld\n' "$NAME" "$LN" >> "$TMP/skips.txt"; continue
    fi
    SCRUBBED=no
    if grep -q '^WARN|' "$FINDINGS"; then SCRUBBED=yes; SCRUB=$((SCRUB+1)); fi

    CANDS=$((CANDS+1))
    if [ "$PRINTED" -lt "$PRINT_MAX" ]; then
      PRINTED=$((PRINTED+1))
      {
        echo "--- candidate $PRINTED ---"
        echo "plan: $PLAN:$LN (stage $STAGE)"
        echo "line: $(printf '%s' "$PLAIN" | redact)"
        echo "paths: $GOOD"
        [ -z "$BAD" ] || echo "unresolved: $BAD"
        [ "$SCRUBBED" = no ] || echo "scrub: credential-shaped words in this text; read before filing"
        printf '%s\n' "$NOTES" | redact | sed '/^$/d'
      } >> "$TMP/cands.txt"
    fi
  done <<ROWS_EOF
$(printf '%s\n' "$ROWS" | grep -v '^$' || true)
ROWS_EOF
done < <(find "$PLAN_DIR" -maxdepth 1 -type f -name '*.md' 2>/dev/null | sort -r)

# ==============
# TELEMETRY
# ==============
DAY=$(date +%F)
AUDIT_FILE=".construct/gitgud/nightshift/$DAY.md"
RUN_COUNT=0
if [ -f "$AUDIT_FILE" ]; then
  RUN_COUNT=$(grep -c '^## Nightshift Run #' "$AUDIT_FILE" 2>/dev/null || true)
fi
SKIPPED=$((SK_AGENTIC + SK_FILED + SK_PATH + SK_SECRET))

telemetry_open gitgud:nightshift
telemetry_line repo "$SLUG"
telemetry_line auth "$AUTH_MODE"
telemetry_line head "$HEAD_BRANCH@$HEAD_SHA (trunk is $MAIN_BRANCH)"
telemetry_line label "$LABEL ($LABEL_STATE)"
telemetry_line dedup "$DEDUP, $OPEN_COPILOT open $LABEL issue(s)"
telemetry_line copilot "$COPILOT_STATE"
telemetry_line trunk "$MAIN_BRANCH"
telemetry_line guidance "${GUIDANCE:-none}"
telemetry_line audit_file "$AUDIT_FILE"
telemetry_line next_run "$((RUN_COUNT+1))"
telemetry_line timestamp "$(date '+%Y-%m-%d %H:%M')"
telemetry_line plans "$PLANS_TOTAL total, $PLANS_CLOSED closed, $PLANS_IDLE idle, $PLANS_READ read"
telemetry_line lines "$LIVE live, $WINDOW in the lowest stage, $HELD held behind it"
telemetry_line ignored "$STRUCK struck, $DEFERRED deferred"
telemetry_line skipped "$SKIPPED (agentic $SK_AGENTIC, filed $SK_FILED, path $SK_PATH, secret $SK_SECRET)"
telemetry_line candidates "$CANDS, $PRINTED printed, $SCRUB with a scrub flag"
if [ "$CANDS" -gt "$PRINTED" ]; then
  telemetry_line truncated "$((CANDS - PRINTED)) candidate(s) past the print ceiling of $PRINT_MAX"
fi
telemetry_line warnings "$WARNINGS"
if [ "$HEAD_BRANCH" != "$MAIN_BRANCH" ]; then
  telemetry_line note "HEAD is not $MAIN_BRANCH, so paths were read from a tree the agent will not see"
fi
if [ "$DEDUP" != ok ]; then
  telemetry_line note "dedup is blind, so every filing is refused this run"
fi
echo "--- skipped lines ---"
if [ -s "$TMP/skips.txt" ]; then cat "$TMP/skips.txt"; else echo "none"; fi
if [ "$CANDS" -eq 0 ]; then
  echo "--- candidates: 0 ---"
  echo "nothing qualifies tonight; the skipped lines above say which test each one failed"
else
  cat "$TMP/cands.txt"
fi
block_close

handover_open gitgud:nightshift
handover_note "nothing to paste: the trigger plans, gates twice, then files through this sidecar"
block_close
exit 0

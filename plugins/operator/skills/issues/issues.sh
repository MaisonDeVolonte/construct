#!/bin/bash
# ====================================================
# @file issues.sh - upstream claude-code issue tracker
# ====================================================
# @description
# PAIR
# - sidecar for `/operator:issues` — fetches issue movement, then hands the telemetry to the doc
# - read-only: it greps, fetches and prints; the trigger writes the report it shapes
# - rides plain curl end to end, since the tracked list includes the issue that breaks `gh` (#26466)
# TRACKED
# - a tracked issue is any full claude-code issue url this repo cites outside .construct/
# - each one is fetched individually: state, last update, and the comments inside the window
# - excerpts pass through the shared secret patterns first, since people paste tokens into issues
# TOPICS
# - a bare run covers tracked plus all four topics; a flag scopes the run to what it names
# - `--tracked`, `--sandbox`, `--hooks`, `--plugins`, `--permissions` each carry one query
# - `--since <days>` overrides the window; the default is the newest report date, else 14 days
# AUTH
# - GH_TOKEN rides along when set, masked or real, since the proxy injects on its listed hosts
# - a rejected token falls back to anonymous with a warning, and the value is never printed
# - anonymous runs at 60 core calls an hour, so the telemetry carries the remaining quota
# @see plugins/operator/skills/issues/SKILL.md, plugins/operator/shared/secrets.sh, README.md

set -euo pipefail

# ==============
# PREFLIGHT
# ==============
# the secret patterns sit in the shared tree: resolve from this file before anything cds,
# since BASH_SOURCE arrives relative and cwd holds no plugins/ once installed from a marketplace
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)
SHARED=$(cd "$HERE/../../shared" 2>/dev/null && pwd || true)
if [ ! -f "$SHARED/secrets.sh" ]; then
  echo "fatal: no shared/secrets.sh reachable from this sidecar" >&2; exit 1; fi
# shellcheck source=../../shared/secrets.sh
. "$SHARED/secrets.sh"

command -v jq >/dev/null 2>&1 || { echo "fatal: jq is required" >&2; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "fatal: curl is required" >&2; exit 1; }

REPO="anthropics/claude-code"
API="https://api.github.com"
ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
ARTIFACTS="$ROOT/.construct/operator/issues"
EXCLUDES="--exclude-dir=.git --exclude-dir=.construct --exclude-dir=node_modules --exclude-dir=tmp"

TMP=$(mktemp -d "${TMPDIR:-/tmp}/issues.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
BODY="$TMP/body.json"

ERRORS=0
WARNINGS=0

# ==============
# FLAGS
# ==============
usage() {
  echo "usage: issues.sh [--tracked] [--sandbox] [--hooks] [--plugins] [--permissions] [--since <days>]"
  echo "a bare run covers tracked plus every topic; each flag scopes the run to what it names"
}

RUN_TRACKED=0; RUN_SANDBOX=0; RUN_HOOKS=0; RUN_PLUGINS=0; RUN_PERMISSIONS=0
SINCE_DAYS=""
while [ $# -gt 0 ]; do
  case "$1" in
    --tracked) RUN_TRACKED=1;;
    --sandbox) RUN_SANDBOX=1;;
    --hooks) RUN_HOOKS=1;;
    --plugins) RUN_PLUGINS=1;;
    --permissions) RUN_PERMISSIONS=1;;
    --since) shift; SINCE_DAYS="${1:-}";;
    --help) usage; exit 0;;
    *) usage >&2; exit 2;;
  esac
  shift
done
if [ $((RUN_TRACKED+RUN_SANDBOX+RUN_HOOKS+RUN_PLUGINS+RUN_PERMISSIONS)) -eq 0 ]; then
  RUN_TRACKED=1; RUN_SANDBOX=1; RUN_HOOKS=1; RUN_PLUGINS=1; RUN_PERMISSIONS=1; fi

SCOPE=""
[ "$RUN_TRACKED" = 1 ] && SCOPE="$SCOPE tracked"
[ "$RUN_SANDBOX" = 1 ] && SCOPE="$SCOPE sandbox"
[ "$RUN_HOOKS" = 1 ] && SCOPE="$SCOPE hooks"
[ "$RUN_PLUGINS" = 1 ] && SCOPE="$SCOPE plugins"
[ "$RUN_PERMISSIONS" = 1 ] && SCOPE="$SCOPE permissions"

# ==============
# WINDOW
# ==============
# the window answers "since when counts as movement": an explicit --since wins, then the newest
# report date, since that is literally the last time anyone looked, then a two week default
if [ -n "$SINCE_DAYS" ]; then
  case "$SINCE_DAYS" in
    ''|*[!0-9]*) echo "fatal: --since wants a day count, got '$SINCE_DAYS'" >&2; exit 2;;
  esac
  SINCE=$(date -v-"${SINCE_DAYS}"d +%F 2>/dev/null || date -d "$SINCE_DAYS days ago" +%F)
  WINDOW_SOURCE="--since $SINCE_DAYS"
else
  LAST=$(ls "$ARTIFACTS"/*.md 2>/dev/null | sed 's|.*/||; s|\.md$||' \
    | grep -E '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' | sort | tail -1 || true)
  if [ -n "$LAST" ]; then
    SINCE="$LAST"; WINDOW_SOURCE="last report"
  else
    SINCE=$(date -v-14d +%F 2>/dev/null || date -d '14 days ago' +%F)
    WINDOW_SOURCE="default 14d"
  fi
fi

# ==============
# AUTH
# ==============
# the masked value is sent as-is on purpose: the sandbox proxy swaps it on its inject hosts,
# and a probe against /rate_limit tells the truth about whether that swap actually happened
AUTH_HEADER=""
AUTH_MODE="anonymous"
GH_AUTH=${GH_TOKEN:-}
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
RATE=$(curl -sS --max-time 20 ${AUTH_HEADER:+-H "$AUTH_HEADER"} "$API/rate_limit" 2>/dev/null \
  | jq -r '"\(.resources.core.remaining)/\(.resources.core.limit) core, " +
           "\(.resources.search.remaining)/\(.resources.search.limit) search"' 2>/dev/null \
  || echo "unreadable")
case "$RATE" in
  unreadable) WARNINGS=$((WARNINGS+1));;
esac

# ==============
# HELPERS
# ==============
# fetches never abort the run: gh_api echoes the http code and the caller decides what it means
gh_api() {
  curl -sS -o "$BODY" -w '%{http_code}' --max-time 20 \
    -H "Accept: application/vnd.github+json" \
    ${AUTH_HEADER:+-H "$AUTH_HEADER"} "$1" 2>/dev/null || echo 000
}

# \001 as the sed delimiter, since the secret patterns themselves carry /, | and @
SEP=$(printf '\001')
redact() {
  LC_ALL=C sed -E "s${SEP}${SECRET_PATTERNS}${SEP}[redacted]${SEP}g"
}

# ==============
# TELEMETRY
# ==============
DAY=$(date +%F)
AUDIT_FILE=".construct/operator/issues/$DAY.md"
REPORT_COUNT=0
if [ -f "$ROOT/$AUDIT_FILE" ]; then
  REPORT_COUNT=$(grep -c '^## Issues Report #' "$ROOT/$AUDIT_FILE" 2>/dev/null || echo 0)
fi

echo "=== issues.sh sidecar ==="
echo "audit_file: $AUDIT_FILE"
echo "next_report: $((REPORT_COUNT+1))"
echo "timestamp: $(date '+%Y-%m-%d %H:%M')"
echo "repo: $REPO"
echo "window: updated since $SINCE ($WINDOW_SOURCE)"
echo "auth: $AUTH_MODE (rate: $RATE)"
echo "scope:$SCOPE"

# ==============
# TRACKED
# ==============
TRACKED_LIST=""
MOVED=0
TRACKED_FAILED=0
if [ "$RUN_TRACKED" = 1 ]; then
  # a citation is a full url, so short #NNNN mentions never register; .construct/ is excluded
  # to keep yesterday's report from tracking whatever yesterday's search happened to surface
  # shellcheck disable=SC2086
  TRACKED_LIST=$(grep -rhoE "$REPO/issues/[0-9]+" "$ROOT" $EXCLUDES 2>/dev/null \
    | grep -oE '[0-9]+$' | sort -un | tr '\n' ' ' || true)
  COUNT=$(echo "$TRACKED_LIST" | wc -w | tr -d ' ')
  echo "--- tracked: $COUNT cited ---"
  if [ "$COUNT" = 0 ]; then
    echo "no full $REPO/issues/N urls cited in this repo, so there is nothing to track yet"
    WARNINGS=$((WARNINGS+1))
  fi
  for N in $TRACKED_LIST; do
    CODE=$(gh_api "$API/repos/$REPO/issues/$N")
    if [ "$CODE" != 200 ]; then
      echo "#$N fetch failed (http $CODE)"
      TRACKED_FAILED=$((TRACKED_FAILED+1)); ERRORS=$((ERRORS+1)); continue
    fi
    # joined on a sanitized pipe: tab is ifs whitespace, so an empty closed_at would collapse
    # and pull the title left a field, and this bash strips a \001 outright inside read
    LINE=$(jq -r '[.state, .updated_at[:10], (.comments|tostring),
      ((.closed_at // "")[:10]), (.state_reason // ""),
      (.title | gsub("[\\t\\n\\r|]"; " ") | .[:58])] | join("|")' "$BODY")
    IFS='|' read -r STATE UPDATED COMMENTS CLOSED REASON TITLE <<EOF
$LINE
EOF
    MOVEMENT="quiet"
    if [ "$UPDATED" \> "$SINCE" ] || [ "$UPDATED" = "$SINCE" ]; then MOVEMENT="moved"; fi
    if [ -n "$CLOSED" ] && { [ "$CLOSED" \> "$SINCE" ] || [ "$CLOSED" = "$SINCE" ]; }; then
      MOVEMENT="closed $CLOSED${REASON:+ ($REASON)}"
    fi
    printf '#%-6s %-6s %s  %3sc  %-8s %s\n' "$N" "$STATE" "$UPDATED" "$COMMENTS" "$MOVEMENT" "$TITLE"
    # shellcheck disable=SC2086
    CITED=$(grep -rlE "$REPO/issues/$N" "$ROOT" $EXCLUDES 2>/dev/null \
      | sed "s|^$ROOT/||" | head -3 | paste -sd ',' - | sed 's|,|, |g' || true)
    echo "        cited: ${CITED:-unresolved}"
    if [ "$MOVEMENT" != quiet ]; then
      MOVED=$((MOVED+1))
      WCODE=$(gh_api "$API/repos/$REPO/issues/$N/comments?since=${SINCE}T00:00:00Z&per_page=20")
      if [ "$WCODE" = 200 ]; then
        WCOUNT=$(jq 'length' "$BODY")
        echo "        comments in window: $WCOUNT"
        # no \uXXXX in the class: this jq reads it as literal chars, birthing a 0-u range
        # that spaces out digits and a through u; tr strips the exotic control chars instead
        jq -r '.[-3:][] | [.created_at[:10], .user.login,
          (.body // "" | gsub("[\\t\\n\\r|]"; " "))] | join("|")' "$BODY" \
        | while IFS='|' read -r CDATE CUSER CBODY; do
            EXCERPT=$(printf '%s' "$CBODY" | redact | LC_ALL=C tr '\000-\037' ' ' | cut -c1-160)
            echo "        $CDATE $CUSER: $EXCERPT"
          done
      else
        echo "        comments fetch failed (http $WCODE)"; WARNINGS=$((WARNINGS+1))
      fi
    fi
  done
fi

# ==============
# TOPICS
# ==============
# each topic is one boolean query, sorted by update so the window's noise floats its own signal;
# total_count sizes the tail the fifteen printed rows leave unseen
TOPICS_RUN=0
TOPIC_HITS=0
TOPICS_FAILED=0
run_topic() {
  NAME="$1"; TERMS="$2"
  TOPICS_RUN=$((TOPICS_RUN+1))
  Q="repo:$REPO is:issue updated:>=$SINCE ($TERMS)"
  ENC=$(jq -rn --arg q "$Q" '$q|@uri')
  CODE=$(gh_api "$API/search/issues?q=$ENC&sort=updated&order=desc&per_page=15&advanced_search=true")
  if [ "$CODE" != 200 ]; then
    echo "--- topic $NAME: search failed (http $CODE) ---"
    TOPICS_FAILED=$((TOPICS_FAILED+1)); ERRORS=$((ERRORS+1)); return 0
  fi
  TOTAL=$(jq -r '.total_count' "$BODY")
  TOPIC_HITS=$((TOPIC_HITS+TOTAL))
  echo "--- topic $NAME: $TOTAL in window (top 15 by update) ---"
  jq -r '.items[] | [(.number|tostring), .state, .updated_at[:10], (.comments|tostring),
    (.title | gsub("[\\t\\n\\r|]"; " ") | .[:62])] | join("|")' "$BODY" \
  | while IFS='|' read -r NUM STATE UPDATED COMMENTS TITLE; do
      MARK=""
      case " $TRACKED_LIST " in *" $NUM "*) MARK=" *";; esac
      printf '#%-6s %-6s %s  %3sc  %s%s\n' "$NUM" "$STATE" "$UPDATED" "$COMMENTS" "$TITLE" "$MARK"
    done
}

[ "$RUN_SANDBOX" = 1 ] && run_topic sandbox \
  'sandbox OR seatbelt OR injectHosts OR allowedDomains OR excludedCommands'
[ "$RUN_HOOKS" = 1 ] && run_topic hooks \
  'hooks OR PreToolUse OR PostToolUse OR SessionStart'
[ "$RUN_PLUGINS" = 1 ] && run_topic plugins \
  'plugin OR skill OR marketplace OR "slash command"'
[ "$RUN_PERMISSIONS" = 1 ] && run_topic permissions \
  'permissions OR "deny rule" OR "allow rule" OR "permission mode" OR "settings.json"'

# ==============
# COUNTS
# ==============
echo "--- counts ---"
if [ "$RUN_TRACKED" = 1 ]; then
  echo "tracked: $(echo "$TRACKED_LIST" | wc -w | tr -d ' ') checked, $MOVED moved, $TRACKED_FAILED failed"
fi
if [ "$TOPICS_RUN" -gt 0 ]; then
  echo "topics: $TOPICS_RUN searched, $TOPIC_HITS in window, $TOPICS_FAILED failed"
fi
echo "errors: $ERRORS"
echo "warnings: $WARNINGS"

# a partial run still reports; only a run that fetched nothing at all is unusable
USABLE=0
if [ "$RUN_TRACKED" = 1 ]; then
  TRACKED_TOTAL=$(echo "$TRACKED_LIST" | wc -w | tr -d ' ')
  [ "$TRACKED_TOTAL" -gt "$TRACKED_FAILED" ] && USABLE=1
fi
[ "$TOPICS_RUN" -gt "$TOPICS_FAILED" ] && USABLE=1
[ "$USABLE" = 1 ] || exit 1
exit 0

#!/bin/bash
# =========================================================
# @file issues.sh - open issue triage sidecar for this repo
# =========================================================
# @description
# PAIR
# - sidecar for `/gitgud:issues` — fetches every open issue on this repo's own origin
# - read-only: it fetches, redacts and prints; the trigger writes the report it shapes
# - rides plain curl end to end, since gh cannot verify tls inside the sandbox (#26466)
# SCOPE
# - open issues only, and never a pull request, since a pr is delivery rather than a report
# - no flags beyond --help: the run is the whole scope, so nothing is left to configure
# - the printed order is arrival order; the report reorders by effort, which no script can judge
# CARRY
# - every earlier report in the artifact dir is grepped for each open number
# - a hit means that issue was already triaged, so its verdict is copied forward, not rebuilt
# AUTH
# - GH_TOKEN rides along when set, masked or real, since the proxy injects on its listed hosts
# - a rejected token falls back to anonymous with a warning, and the value is never printed
# @see plugins/gitgud/skills/issues/SKILL.md, plugins/gitgud/shared/secrets.sh

set -euo pipefail

# the doc is read only after this has already run, so help is refused here or not at all; the doc's
# own '## Help' section owns the output, which is why this prints a marker rather than a usage text
case " $* " in *" --help "*|*" -h "*) echo "help: requested"; exit 0;; esac

usage() {
  echo "usage: issues.sh [--help]"
  echo "a bare run triages every open issue on origin; there is nothing else to scope"
}
[ "$#" -eq 0 ] || { usage >&2; exit 2; }

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

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "fatal: not a git repository" >&2; exit 1; fi
ROOT=$(git rev-parse --show-toplevel)

# the slug comes from origin, so the skill triages whatever repo it is run inside; both url
# forms collapse to owner/name, and anything that is not github is refused rather than guessed
ORIGIN=$(git remote get-url origin 2>/dev/null || true)
if [ -z "$ORIGIN" ]; then
  echo "fatal: this repo has no origin remote, so there are no issues to read" >&2; exit 1; fi
SLUG=$(printf '%s' "$ORIGIN" \
  | sed -e 's|^git@github\.com:||' -e 's|^ssh://git@github\.com/||' \
        -e 's|^https://github\.com/||' -e 's|^git://github\.com/||' -e 's|\.git$||')
case "$SLUG" in
  */*) : ;;
  *) echo "fatal: origin is not a github repo: $ORIGIN" >&2; exit 1;;
esac

API="https://api.github.com"
ARTIFACTS="$ROOT/.construct/gitgud/issues"

TMP=$(mktemp -d "${TMPDIR:-/tmp}/gitgud-issues.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
BODY="$TMP/body.json"

ERRORS=0
WARNINGS=0

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
  | jq -r '"\(.resources.core.remaining)/\(.resources.core.limit) core"' 2>/dev/null \
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
AUDIT_FILE=".construct/gitgud/issues/$DAY.md"
REPORT_COUNT=0
if [ -f "$ROOT/$AUDIT_FILE" ]; then
  REPORT_COUNT=$(grep -c '^## Triage Report #' "$ROOT/$AUDIT_FILE" 2>/dev/null || echo 0)
fi
# the artifact dir does not exist before the first run, and find exits 1 on it under pipefail
PRIOR_REPORTS=$(find "$ARTIFACTS" -maxdepth 1 -type f -name '*.md' 2>/dev/null | wc -l | tr -d ' ' || true)

echo "=== issues.sh sidecar ==="
echo "repo: $SLUG"
echo "audit_file: $AUDIT_FILE"
echo "next_report: $((REPORT_COUNT+1))"
echo "timestamp: $(date '+%Y-%m-%d %H:%M')"
echo "auth: $AUTH_MODE (rate: $RATE)"
echo "prior_reports: $PRIOR_REPORTS"

# ==============
# OPEN ISSUES
# ==============
# sorted by creation so the oldest unresolved report leads; effort ordering belongs to the doc,
# since only a reader of the code can say which of these is low hanging fruit
CODE=$(gh_api "$API/repos/$SLUG/issues?state=open&per_page=100&sort=created&direction=asc")
if [ "$CODE" != 200 ]; then
  echo "--- open: fetch failed (http $CODE) ---"
  echo "errors: 1"
  echo "warnings: $WARNINGS"
  exit 1
fi

# a pull request is an issue to this endpoint, so the .pull_request key is what separates them
jq -r '[.[] | select(.pull_request == null)]' "$BODY" > "$TMP/open.json"
OPEN=$(jq 'length' "$TMP/open.json")
RAW=$(jq 'length' "$BODY")
if [ "$RAW" -ge 100 ]; then
  echo "note: the first 100 rows were read, so an older open issue may be unseen"
  WARNINGS=$((WARNINGS+1))
fi

echo "--- open: $OPEN issue(s) ---"
if [ "$OPEN" = 0 ]; then
  echo "nothing open on $SLUG, so there is nothing to triage today"
fi

NEW=0
CARRIED=0
NUMBERS=$(jq -r '.[].number' "$TMP/open.json")
for N in $NUMBERS; do
  LINE=$(jq -r --argjson n "$N" '.[] | select(.number == $n) |
    [(.created_at[:10]), (.updated_at[:10]), (.comments|tostring), (.user.login // "unknown"),
     ([.labels[].name] | join(",") | if . == "" then "none" else . end),
     (.title | gsub("[\\t\\n\\r|]"; " ") | .[:96])] | join("|")' "$TMP/open.json")
  IFS='|' read -r CREATED UPDATED COMMENTS AUTHOR LABELS TITLE <<EOF
$LINE
EOF

  # an earlier report naming this number already carries a verdict, so the doc copies it forward
  # rather than triaging it again; today's own file is excluded, since a rerun is not prior work
  PRIOR=$(grep -rl "#$N\b" "$ARTIFACTS" 2>/dev/null \
    | grep -v "/$DAY\.md$" | sed 's|.*/||' | sort | tail -1 || true)
  if [ -n "$PRIOR" ]; then
    PRIOR_NOTE="$PRIOR"
    CARRIED=$((CARRIED+1))
  else
    PRIOR_NOTE="none"
    NEW=$((NEW+1))
  fi

  EXCERPT=$(jq -r --argjson n "$N" '.[] | select(.number == $n) |
    (.body // "" | gsub("[\\t\\n\\r]"; " "))' "$TMP/open.json" \
    | redact | LC_ALL=C tr '\000-\037' ' ' | cut -c1-240)

  # the three lines between the header and `meta:` are what the report fences verbatim, so they
  # carry only what a reader needs; `meta:` holds the fields the doc reads but never pastes
  echo "--- #$N ---"
  echo "$CREATED | $AUTHOR | prior: $PRIOR_NOTE"
  echo "$TITLE"
  echo "body: ${EXCERPT:-empty}"
  echo "meta: upd $UPDATED, $COMMENTS comment(s), labels: $LABELS"
done

# ==============
# COUNTS
# ==============
echo "--- counts ---"
echo "open: $OPEN, new: $NEW, carried: $CARRIED"
echo "errors: $ERRORS"
echo "warnings: $WARNINGS"
exit 0

#!/bin/bash
# =============================================
# @file gitgud.sh - stale-pr ci refresh sidecar
# =============================================
# @description
# - sidecar for `@gitgud` — re-runs ci on a stale pr against the default branch
# - talks to github through curl + bearer auth since gh cannot verify tls in the sandbox
# @see AGENTS.md, AGENTS/templates/git.md, AGENTS/git/gitgud.md, README.md

set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)
if [ ! -f "$HERE/handover.sh" ]; then
  echo "fatal: no AGENTS/git/handover.sh beside this sidecar" >&2; exit 1; fi
# shellcheck source=./handover.sh
. "$HERE/handover.sh"

WATCH="false"
for arg in "$@"; do
  case "$arg" in
    --watch) WATCH="true" ;;
    *) echo "fatal: unknown argument '$arg' (the only flag is --watch)" >&2; exit 1;;
  esac
done

# GUARDS

require_repo
require_tools curl jq
require_no_op_in_progress

# check the github token is present; inside the sandbox it holds the masked sentinel
# the proxy swaps for the real value — outside it holds the real token (curl takes both)
if [ -z "${GH_TOKEN:-}" ]; then
  echo "fatal: GH_TOKEN is not set (see README.md > Settings > Keys)" >&2; exit 1; fi

DEFAULT_BRANCH=$(git_default_branch)
if [ -z "$DEFAULT_BRANCH" ]; then
  echo "fatal: missing remote default branch" >&2; exit 1; fi

# owner/repo parsed from the origin url in both its https and ssh shapes
REMOTE_URL=$(git remote get-url origin 2>/dev/null || echo "")
if ! echo "$REMOTE_URL" | grep -q 'github\.com'; then
  echo "fatal: origin is not a github remote" >&2; exit 1; fi
REPO_SLUG=$(echo "$REMOTE_URL" | sed -e 's#^.*github\.com[:/]##' -e 's#\.git$##')
REPO_OWNER=${REPO_SLUG%%/*}
GITHUB_API="https://api.github.com"

# every github call goes through curl with a bearer header, the one auth shape the mask
# proxy can substitute (see README.md > Settings > Keys > GitHub)
github_api() {
  curl -sS --max-time 30 \
    -H "Authorization: Bearer $GH_TOKEN" \
    -H "Accept: application/vnd.github+json" \
    "$@"
}

# prove the token authenticates before reading anything else
AUTH_CODE=$(github_api -o /dev/null -w '%{http_code}' "$GITHUB_API/user" 2>/dev/null || echo 000)
if [ "$AUTH_CODE" != "200" ]; then
  echo "fatal: github api auth failed (http $AUTH_CODE)" >&2; exit 1; fi

# the current branch names the pr; forks aren't supported so the head owner is the repo owner
CURRENT_BRANCH=$(git branch --show-current)
if [ -z "$CURRENT_BRANCH" ]; then
  echo "fatal: detached HEAD (run @gitgud from the pr branch)" >&2; exit 1; fi

# always target the open pr for the branch you're sitting on — number, refs, and url arrive
# in one list query; mergeability only computes on the single-pr endpoint read next
PR_INFO=$(github_api "$GITHUB_API/repos/$REPO_SLUG/pulls?state=open&head=$REPO_OWNER:$CURRENT_BRANCH" 2>/dev/null \
  | jq -r '.[0] // empty | [.number, .head.ref, .base.ref, .html_url] | @tsv' 2>/dev/null || echo "")
if [ -z "$PR_INFO" ]; then
  echo "fatal: no open pr for the current branch (run @gitgud from the pr branch)" >&2; exit 1; fi
IFS=$'\t' read -r PR_NUMBER PR_HEAD PR_BASE PR_URL <<< "$PR_INFO"

# github computes mergeability lazily and first reads often say unknown — ask a few times
# then proceed; a real conflict still fails the update call below with a clear message
PR_MERGESTATE="unknown"
for _ in 1 2 3 4 5; do
  PR_MERGESTATE=$(github_api "$GITHUB_API/repos/$REPO_SLUG/pulls/$PR_NUMBER" 2>/dev/null \
    | jq -r '.mergeable_state // "unknown"' 2>/dev/null || echo "unknown")
  if [ "$PR_MERGESTATE" != "unknown" ]; then break; fi
  sleep 2
done

# a conflicted pr can't be updated through the api — the base merge would fail
if [ "$PR_MERGESTATE" = "dirty" ]; then
  echo "fatal: pr #$PR_NUMBER conflicts with $DEFAULT_BRANCH (resolve locally; ci won't clear on its own)" >&2; exit 1; fi

# sync the branches we compare; forks aren't supported (their head isn't on origin)
if ! git fetch origin "$DEFAULT_BRANCH" "$PR_HEAD" --quiet 2>/dev/null; then
  echo "fatal: could not fetch $PR_HEAD or $DEFAULT_BRANCH from origin (same-repo prs only)" >&2; exit 1; fi

# how many commits the trunk has that this pr hasn't absorbed — the staleness signal
BEHIND_COUNT=$(git rev-list --count "origin/$PR_HEAD..origin/$DEFAULT_BRANCH" 2>/dev/null || echo "0")

# nothing stale to fix → a red run here is a real failure, not a base problem
if [ "$BEHIND_COUNT" -eq 0 ]; then
  echo "fatal: pr #$PR_NUMBER already contains all of $DEFAULT_BRANCH — any ci failure is real, read the logs at $PR_URL" >&2; exit 1; fi

# EXECUTION

# the newest workflow run on the pr branch, used to tell a fresh run from the one before it
latest_run_id() {
  github_api "$GITHUB_API/repos/$REPO_SLUG/actions/runs?branch=$PR_HEAD&per_page=1" 2>/dev/null \
    | jq -r '.workflow_runs[0].id // empty' 2>/dev/null || true
}

# watch mode needs the current top run so it can spot the fresh one after re-triggering
if [ "$WATCH" = "true" ]; then
  OLD_RUN_ID=$(latest_run_id)
fi

# merge the fresh trunk into the pr branch → fires a synchronize event → ci rebuilds against
# the current trunk; 202 accepted is the api's only success answer here
UPDATE_CODE=$(github_api -o /dev/null -w '%{http_code}' -X PUT \
  "$GITHUB_API/repos/$REPO_SLUG/pulls/$PR_NUMBER/update-branch" 2>/dev/null || echo 000)
if [ "$UPDATE_CODE" != "202" ]; then
  echo "fatal: could not update pr #$PR_NUMBER branch, http $UPDATE_CODE (422 conflicts or protected branch; 403 the token lacks write — see README.md > Settings > Keys)" >&2; exit 1; fi
RESULT="redelivered"

# the default returns here; --watch follows the fresh run to green or red
if [ "$WATCH" = "true" ]; then
  # wait for the fresh run to register as a new id at the top of the list
  RUN_ID="$OLD_RUN_ID"
  ATTEMPTS=0
  while [ "$RUN_ID" = "$OLD_RUN_ID" ] && [ "$ATTEMPTS" -lt 15 ]; do
    sleep 2
    RUN_ID=$(latest_run_id)
    if [ -z "$RUN_ID" ]; then RUN_ID="$OLD_RUN_ID"; fi
    ATTEMPTS=$((ATTEMPTS + 1))
  done
  if [ "$RUN_ID" = "$OLD_RUN_ID" ] || [ -z "$RUN_ID" ]; then
    echo "fatal: redelivered pr #$PR_NUMBER but a fresh ci run never registered (check $PR_URL)" >&2; exit 1; fi

  # follow the run until github marks it completed and let the conclusion pick green or red
  # an hour without completing also reads as red, the fail-safe answer
  RUN_CONCLUSION=""
  WAITED=0
  while [ "$WAITED" -lt 3600 ]; do
    RUN_JSON=$(github_api "$GITHUB_API/repos/$REPO_SLUG/actions/runs/$RUN_ID" 2>/dev/null || echo '{}')
    RUN_STATUS=$(echo "$RUN_JSON" | jq -r '.status // empty' 2>/dev/null || echo "")
    if [ "$RUN_STATUS" = "completed" ]; then
      RUN_CONCLUSION=$(echo "$RUN_JSON" | jq -r '.conclusion // empty' 2>/dev/null || echo "")
      break
    fi
    sleep 10
    WAITED=$((WAITED + 10))
  done
  if [ "$RUN_CONCLUSION" = "success" ]; then
    RESULT="green"
  else
    RESULT="red"
  fi
fi

# TELEMETRY

cat <<EOF
=== @gitgud redelivery ===
PR: #$PR_NUMBER ($PR_HEAD → $PR_BASE)
ABSORBED: $BEHIND_COUNT commit(s) from $DEFAULT_BRANCH
ACTION: merged $DEFAULT_BRANCH into $PR_HEAD (synchronize event)
RESULT: $RESULT
URL: $PR_URL
==========================
EOF

# a red run is a real failure now that the base is fresh
if [ "$RESULT" = "red" ]; then
  echo "fatal: ci still red after redelivery — the failure is real, inspect: $PR_URL" >&2
  exit 1
fi

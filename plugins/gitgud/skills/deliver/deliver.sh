#!/bin/bash
# =============================================================
# @file deliver.sh - atomic delivery preflight and github writer
# =============================================================
# @description
# PAIR
# - sidecar for `/gitgud:deliver` — proves auth and state, then writes each bucket to github
# - the trigger drains uncommitted work in atomic `type(scope)` buckets, one pr per bucket
# - a bucket is one branch, one commit, one pr and auto-merge, all written by this file
# - the reasoning is the automation: bucketing, ordering and message drafting are what it does
# GATE
# - it plans EVERY bucket first and stops there, since a wrong bucket is free to fix before a branch
# - the drain is a second gate: nothing is written until the user answers the plan with `go`
# - `--debug` plans everything the same way, but drains only the first bucket
# - `--finished` buckets only work that reads as finished, leaving unfinished files in the tree
# - `--handover` emits the git and gh commands instead of writing, for a terminal that can push
# SHAPE
# - no subcommand runs the preflight: auth, state, issues, telemetry, then the prep block
# - `bucket` turns a file list into one branch, one commit, one pull request, auto-merge armed
# - `update` moves an existing branch onto a new commit, which is how a red pr gets fixed
# - `watch` polls the required check, then reports whether the pull request actually merged
# - `state` prints the trunk sha and the open pull request count, which callers gate on
# - `probe` replays a bucket's drain command through the live pretooluse gate, deny exits 1
# CONFIG
# - `construct.config.json` at the repo root carries the branch, merge and queue settings
# - `~/.construct/config.json` carries the identities, since those belong to a person not a repo
# - a project key wins over a user key, and a missing key falls back to the default named here
# - `merge_queue: true` means the queue serializes and rebases, so the watch returns immediately
# WRITES
# - every write is a curl call against api.github.com, the one host the mask injects into
# - the local worktree is never touched: files are read, never staged, moved or reverted
# - go binaries never load the sandbox ca, so `gh` fails for a second, unrelated reason
# - a tree api commit is atomic across many files, which a paste of several commands is not
# - every open issue on origin is printed, so a bucket that fixes one can close it on merge
# - a delivered `.claude/settings.json` strands its checkout, so the pull after needs the hatch
# @see plugins/gitgud/skills/deliver/SKILL.md, plugins/gitgud/shared/handover.sh, .claude/skills/validate-skills/SKILL.md

set -euo pipefail

# the doc is read only after this has already run, so help is refused here or not at all; the doc's
# own '## Help' section owns the output, which is why this prints a marker rather than a usage text
case " $* " in *" --help "*|*" -h "*) echo "help: requested"; exit 0;; esac

# the smoke case proves this file parses and its guards return; /test-skills reads the sources,
# the @see paths and the tool guards statically, so nothing here runs a step of the skill
case " $* " in *" --test "*) echo "test: ok"; exit 0;; esac

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)
SHARED=$(cd "$HERE/../../shared" 2>/dev/null && pwd || true)
if [ ! -f "$SHARED/handover.sh" ]; then
  echo "fatal: no plugins/gitgud/shared/handover.sh reachable from this sidecar" >&2; exit 1; fi
# shellcheck source=../../shared/handover.sh
. "$SHARED/handover.sh"

die() { echo "fatal: $1" >&2; exit 1; }

require_repo
require_tools curl jq

# every path below is repo-relative, since a bucket names the files the way git status printed them
ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"

# check the github token is present; inside the sandbox it holds the masked sentinel
# the proxy swaps for the real value — outside it holds the real token (curl takes both)
[ -n "${GH_TOKEN_OPERATOR:-}" ] || die "GH_TOKEN_OPERATOR is not set (see README.md > Settings > Keys)"

API="https://api.github.com"

SLUG=$(git remote get-url origin 2>/dev/null \
  | sed -e 's|^git@github\.com:||' -e 's|^ssh://git@github\.com/||' \
        -e 's|^https://github\.com/||' -e 's|\.git$||')

PROJECT_CONFIG="$ROOT/construct.config.json"
USER_CONFIG="$HOME/.construct/config.json"

# one key, read from the project first and the user second, so a repo setting wins over a personal
# one and an absent file costs nothing; `cfg .github.merge_method rebase` is the whole shape
cfg() {
  local path=$1 fallback=${2:-} value=''
  if [ -r "$PROJECT_CONFIG" ]; then
    value=$(jq -r "$path // empty" "$PROJECT_CONFIG" 2>/dev/null || true); fi
  if [ -z "$value" ] && [ -r "$USER_CONFIG" ]; then
    value=$(jq -r "$path // empty" "$USER_CONFIG" 2>/dev/null || true); fi
  printf '%s' "${value:-$fallback}"
}

MERGE_METHOD=$(cfg .github.merge_method rebase)
AUTO_MERGE=$(cfg .github.auto_merge true)
MERGE_QUEUE=$(cfg .github.merge_queue false)
WATCH_MERGE=$(cfg .github.watch_merge true)
COMMIT_AUTHOR=$(cfg .github.commit_author_username)
COMMIT_EMAIL=$(cfg .github.commit_author_email)
CO_AUTHOR=$(cfg .github.co_author_username)
CO_EMAIL=$(cfg .github.co_author_email)

# ==============
# API
# ==============
# every call carries the same headers, and every failure prints the api's own message rather than
# a paraphrase, since a 422 body names the field that was wrong
api() {
  local method=$1 path=$2 body=${3:-} out code
  out=$(mktemp "${TMPDIR:-/tmp}/gitgud-api.XXXXXX")
  if [ -n "$body" ]; then
    code=$(curl -sS --max-time 30 -o "$out" -w '%{http_code}' -X "$method" \
      -H "Authorization: Bearer $GH_TOKEN_OPERATOR" -H "Accept: application/vnd.github+json" \
      -d "$body" "$API$path" || echo 000)
  else
    code=$(curl -sS --max-time 30 -o "$out" -w '%{http_code}' -X "$method" \
      -H "Authorization: Bearer $GH_TOKEN_OPERATOR" -H "Accept: application/vnd.github+json" \
      "$API$path" || echo 000)
  fi
  case "$code" in
    2*) cat "$out"; rm -f "$out";;
    *) echo "api $method $path failed (http $code)" >&2; cat "$out" >&2; rm -f "$out"; return 1;;
  esac
}

# graphql is the only endpoint that arms auto-merge; rest has no equivalent field
graphql() {
  local query=$1 out code
  out=$(mktemp "${TMPDIR:-/tmp}/gitgud-gql.XXXXXX")
  code=$(curl -sS --max-time 30 -o "$out" -w '%{http_code}' -X POST \
    -H "Authorization: Bearer $GH_TOKEN_OPERATOR" \
    -d "$(jq -n --arg q "$query" '{query: $q}')" "$API/graphql" || echo 000)
  if [ "$code" != 200 ]; then
    echo "graphql failed (http $code)" >&2; cat "$out" >&2; rm -f "$out"; return 1; fi
  cat "$out"; rm -f "$out"
}

trunk_sha() { api GET "/repos/$SLUG/git/ref/heads/$1" | jq -r '.object.sha'; }

# graphql takes the method as an enum, so the config's lowercase word is uppercased here
arm_auto_merge() {
  local prid=$1 method
  method=$(printf '%s' "$MERGE_METHOD" | tr '[:lower:]' '[:upper:]')
  graphql "mutation { enablePullRequestAutoMerge(input: {pullRequestId: \"$prid\", mergeMethod: $method}) { clientMutationId } }" \
    | jq -e '.errors | not' >/dev/null 2>&1
}

# a path the worktree no longer has is a deletion, and the tree api takes a null sha for one; a
# path it does have is uploaded whole, base64, so a binary file survives the round trip unchanged
tree_entry() {
  local path=$1 mode sha
  if [ ! -e "$path" ]; then
    jq -n --arg p "$path" '{path: $p, mode: "100644", type: "blob", sha: null}'
    return 0
  fi
  mode=100644
  [ -x "$path" ] && mode=100755
  sha=$(api POST "/repos/$SLUG/git/blobs" \
    "$(jq -n --arg c "$(base64 < "$path" | tr -d '\n')" '{content: $c, encoding: "base64"}')" \
    | jq -r '.sha')
  [ -n "$sha" ] && [ "$sha" != null ] || die "blob upload returned no sha for $path"
  jq -n --arg p "$path" --arg m "$mode" --arg s "$sha" \
    '{path: $p, mode: $m, type: "blob", sha: $s}'
}

# the trailer credits the other identity, since a commit carries one author and a pr one opener
commit_body() {
  local body=$1
  if [ -n "$CO_AUTHOR" ] && [ -n "$CO_EMAIL" ]; then
    printf '%s\n\nCo-Authored-By: %s <%s>\n' "$body" "$CO_AUTHOR" "$CO_EMAIL"
  else
    printf '%s\n' "$body"
  fi
}

# an omitted committer copies the author rather than the token's account, so both are sent by name;
# the human wrote it and the machine created the commit, which is what %an and %cn then report
commit_payload() {
  local message=$1 tree=$2 parent=$3 payload
  payload=$(jq -n --arg m "$message" --arg t "$tree" --arg p "$parent" \
    '{message: $m, tree: $t, parents: [$p]}')
  if [ -n "$COMMIT_AUTHOR" ] && [ -n "$COMMIT_EMAIL" ]; then
    payload=$(printf '%s' "$payload" | jq --arg n "$COMMIT_AUTHOR" --arg e "$COMMIT_EMAIL" \
      '. + {author: {name: $n, email: $e}}')
  fi
  if [ -n "$CO_AUTHOR" ] && [ -n "$CO_EMAIL" ]; then
    payload=$(printf '%s' "$payload" | jq --arg n "$CO_AUTHOR" --arg e "$CO_EMAIL" \
      '. + {committer: {name: $n, email: $e}}')
  fi
  printf '%s' "$payload"
}

# every path in one tree, built on the base commit's tree so untouched files carry through
tree_of() {
  local basetree=$1; shift
  local entries='[]' path
  for path in "$@"; do
    entries=$(printf '%s\n%s' "$entries" "$(tree_entry "$path")" | jq -s '.[0] + [.[1]]')
  done
  api POST "/repos/$SLUG/git/trees" \
    "$(jq -n --arg b "$basetree" --argjson t "$entries" '{base_tree: $b, tree: $t}')" | jq -r '.sha'
}

# ==============
# SUBCOMMANDS
# ==============
# one branch and one commit carrying every path; the caller owns the ordering between buckets
cmd_bucket() {
  local base=$1 branch=$2 title=$3 bodyfile=$4; shift 4
  [ $# -gt 0 ] || die "bucket needs at least one path"
  [ -f "$bodyfile" ] || die "no commit body file at $bodyfile"

  local basesha basetree treesha commitsha body prnum prid armed=off
  basesha=$(trunk_sha "$base")
  basetree=$(api GET "/repos/$SLUG/git/commits/$basesha" | jq -r '.tree.sha')
  treesha=$(tree_of "$basetree" "$@")

  body=$(commit_body "$(cat "$bodyfile")")
  commitsha=$(api POST "/repos/$SLUG/git/commits" \
    "$(commit_payload "$title

$body" "$treesha" "$basesha")" | jq -r '.sha')

  api POST "/repos/$SLUG/git/refs" \
    "$(jq -n --arg r "refs/heads/$branch" --arg s "$commitsha" '{ref: $r, sha: $s}')" >/dev/null

  prnum=$(api POST "/repos/$SLUG/pulls" \
    "$(jq -n --arg t "$title" --arg h "$branch" --arg b "$base" --arg d "$body" \
      '{title: $t, head: $h, base: $b, body: $d}')" | jq -r '.number')

  if [ "$AUTO_MERGE" = true ]; then
    prid=$(api GET "/repos/$SLUG/pulls/$prnum" | jq -r '.node_id')
    armed=yes
    arm_auto_merge "$prid" || armed=no
  fi

  printf 'branch: %s\ncommit: %s\npr: %s\nauthor: %s\nauto-merge: %s\nfiles: %s\n' \
    "$branch" "${commitsha:0:7}" "$prnum" "${COMMIT_AUTHOR:-token account}" "$armed" "$#"
}

# a red bucket is fixed in place: same branch, new commit on its tip, and the pr updates itself
cmd_update() {
  local branch=$1 title=$2 bodyfile=$3; shift 3
  [ $# -gt 0 ] || die "update needs at least one path"
  [ -f "$bodyfile" ] || die "no commit body file at $bodyfile"

  local tipsha tiptree treesha commitsha body
  tipsha=$(trunk_sha "$branch")
  tiptree=$(api GET "/repos/$SLUG/git/commits/$tipsha" | jq -r '.tree.sha')
  treesha=$(tree_of "$tiptree" "$@")

  body=$(commit_body "$(cat "$bodyfile")")
  commitsha=$(api POST "/repos/$SLUG/git/commits" \
    "$(commit_payload "$title

$body" "$treesha" "$tipsha")" | jq -r '.sha')

  # no force: a non-fast-forward here means the branch moved under us, which should fail loudly
  api PATCH "/repos/$SLUG/git/refs/heads/$branch" \
    "$(jq -n --arg s "$commitsha" '{sha: $s, force: false}')" >/dev/null

  printf 'branch: %s\ncommit: %s\nparent: %s\nfiles: %s\n' \
    "$branch" "${commitsha:0:7}" "${tipsha:0:7}" "$#"
}

# the check decides whether a pr may merge, so this waits on it first and reports the merge second
# a merge queue removes that race itself, since it serializes and rebases each pr on the way in
cmd_watch() {
  local prnum=$1 tries=${2:-60} pr sha status conclusion merged
  local n=0
  if [ "$MERGE_QUEUE" = true ]; then
    printf 'pr: %s\nqueue: enqueued\nmerged: pending\n' "$prnum"
    return 0
  fi
  while [ "$n" -lt "$tries" ]; do
    pr=$(api GET "/repos/$SLUG/pulls/$prnum")
    merged=$(printf '%s' "$pr" | jq -r '.merged')
    sha=$(printf '%s' "$pr" | jq -r '.head.sha')
    if [ "$merged" = true ]; then
      printf 'pr: %s\nchecks: %s\nmerged: yes\n' "$prnum" "${conclusion:-success}"
      return 0
    fi
    status=$(api GET "/repos/$SLUG/commits/$sha/check-runs" \
      | jq -r '[.check_runs[]?.status] | if length == 0 then "queued" elif all(. == "completed") then "completed" else "running" end')
    if [ "$status" = completed ]; then
      conclusion=$(api GET "/repos/$SLUG/commits/$sha/check-runs" \
        | jq -r '[.check_runs[]?.conclusion] | if all(. == "success") then "success" else "failure" end')
      if [ "$conclusion" != success ]; then
        printf 'pr: %s\nchecks: failure\nmerged: no\n' "$prnum"
        return 1
      fi
      # a repo that merges by hand still wants the green light reported, not a five minute wait
      if [ "$WATCH_MERGE" != true ]; then
        printf 'pr: %s\nchecks: success\nmerged: not awaited\n' "$prnum"
        return 0
      fi
    fi
    n=$((n + 1))
    sleep 5
  done
  printf 'pr: %s\nchecks: %s\nmerged: no\n' "$prnum" "${conclusion:-timeout}"
  return 1
}

cmd_state() {
  local base=${1:-$(cfg .github.main_branch main)}
  printf 'repo: %s\ntrunk: %s\ntrunk sha: %s\nopen prs: %s\n' \
    "$SLUG" "$base" "$(trunk_sha "$base" | cut -c1-7)" \
    "$(api GET "/repos/$SLUG/pulls?state=open&per_page=100" | jq 'length')"
  printf 'merge method: %s\nauto-merge: %s\nmerge queue: %s\nwatch merge: %s\n' \
    "$MERGE_METHOD" "$AUTO_MERGE" "$MERGE_QUEUE" "$WATCH_MERGE"
  printf 'commit author: %s\nco-author: %s\n' \
    "${COMMIT_AUTHOR:-token account}" "${CO_AUTHOR:-none}"
}

# replays the drain's own command through the live gate, the way operator:permissions replays
# its corpus: the gate authors every handback, and an unreachable gate degrades to `attempt`
cmd_probe() {
  local files="$*" gatedir='' action out decision denied='' reason=''
  [ -n "$files" ] || die "probe needs a bucket's file list"
  # the operator plugin is a sibling in a source checkout and in a marketplace install alike
  for gatedir in "$HERE/../../../operator/hooks/pretooluse" "$ROOT/plugins/operator/hooks/pretooluse"; do
    if [ -d "$gatedir" ]; then break; fi
    gatedir=''
  done
  local cmd="deliver.sh bucket base branch commit body.md $files"
  printf 'command: %s\n' "$cmd"
  if [ -z "$gatedir" ]; then
    printf 'gate: unreachable\nverdict: attempt\n'
    return 0
  fi
  printf 'gate: %s\n' "$gatedir"
  for action in "$gatedir"/*.sh; do
    [ -f "$action" ] || continue
    out=$(jq -n --arg c "$cmd" '{tool_input:{command:$c}}' | bash "$action" 2>/dev/null || true)
    [ -n "$out" ] || continue
    decision=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null || true)
    if [ "$decision" = deny ]; then
      denied=$(basename "$action" .sh)
      reason=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty' 2>/dev/null || true)
      break
    fi
  done
  if [ -n "$denied" ]; then
    printf 'verdict: deny (%s)\nreason: %s\n' "$denied" "$reason"
    return 1
  fi
  printf 'verdict: allow\n'
}

# a subcommand is the drain calling back in mid-run, so it writes and exits before the preflight
# below re-measures a tree it already measured; a bare invocation falls through to that preflight
case "${1:-}" in
  probe)
    CMD=$1; shift
    cmd_probe "$@"
    exit $?
    ;;
  bucket|update|watch|state)
    case "$SLUG" in */*) ;; *) die "origin is not a github remote";; esac
    CMD=$1; shift
    "cmd_$CMD" "$@"
    exit $?
    ;;
esac

# ==============
# PREFLIGHT
# ==============
require_no_op_in_progress

# free text left after the flags is the user's bucketing guidance, echoed rather than acted on
# here; the trigger reads it out of the telemetry, since only the model does the bucketing
GUIDANCE=''
ARGV=()
if [ -n "$*" ]; then read -ra ARGV <<< "$*"; fi
for word in ${ARGV[@]+"${ARGV[@]}"}; do
  case "$word" in
    --debug|--finished|--handover|--help|-h) continue;;
    *) GUIDANCE="${GUIDANCE:+$GUIDANCE }$word";;
  esac
done
GUIDANCE=${GUIDANCE//\"/}

# prove the token authenticates before the delivery loop starts; bearer auth is the one
# shape the mask proxy can substitute (see plugins/operator/settings/settings.user.md > github)
AUTH_CODE=$(curl -sS --max-time 15 -o /dev/null -w '%{http_code}' \
  -H "Authorization: Bearer $GH_TOKEN_OPERATOR" https://api.github.com/user 2>/dev/null || echo 000)
if [ "$AUTH_CODE" != "200" ]; then
  echo "fatal: github api auth failed (http $AUTH_CODE)" >&2; exit 1; fi

DEFAULT_BRANCH=$(git_default_branch)
CURRENT_BRANCH=$(git_current_branch)

if [ -z "$DEFAULT_BRANCH" ]; then
  echo "fatal: missing remote default branch" >&2; exit 1; fi
if [ -z "$CURRENT_BRANCH" ]; then
  echo "fatal: detached HEAD" >&2; exit 1; fi

# there is nothing to bucket without uncommitted work, and the loop below assumes there is
if ! git_is_dirty; then
  echo "fatal: working tree clean" >&2; exit 1; fi

FETCH_ERR=""
if ! FETCH_ERR=$(git fetch origin "$DEFAULT_BRANCH" --quiet 2>&1); then
  echo "fatal: could not fetch origin/$DEFAULT_BRANCH" >&2
  echo "$FETCH_ERR" >&2
  exit 1
fi

BEHIND=$(git rev-list --count "$DEFAULT_BRANCH..origin/$DEFAULT_BRANCH" 2>/dev/null || echo 0)
AHEAD=$(git rev-list --count "origin/$DEFAULT_BRANCH..$DEFAULT_BRANCH" 2>/dev/null || echo 0)
CHANGED_FILES=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
STAGED_FILES=$(git diff --cached --name-only 2>/dev/null | wc -l | tr -d ' ')

# a delivery touching this path strands its own checkout, so the loop needs to know up front
TOUCHES_SETTINGS=no
if git status --porcelain 2>/dev/null | grep -q '\.claude/settings\.json'; then
  TOUCHES_SETTINGS=yes
fi

# open issues ride along, so a bucket that fixes one can carry a closing trailer into its pr
# the read is advisory: a failed fetch costs the linking rather than the delivery
ISSUES_BODY=$(mktemp "${TMPDIR:-/tmp}/gitgud-deliver.XXXXXX")
trap 'rm -f "$ISSUES_BODY"' EXIT
ISSUES_URL="$API/repos/$SLUG/issues"
ISSUES_URL="$ISSUES_URL?state=open&per_page=100&sort=created&direction=asc"
ISSUES_CODE="origin is not github"
case "$SLUG" in */*) ISSUES_CODE=fetch;; esac
if [ "$ISSUES_CODE" = fetch ]; then
  ISSUES_CODE=$(curl -sS --max-time 15 -o "$ISSUES_BODY" -w '%{http_code}' \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer $GH_TOKEN_OPERATOR" "$ISSUES_URL" 2>/dev/null || echo 000)
fi

# this endpoint counts a pull request as an issue, so the pull_request stub is what separates them
OPEN_ISSUES=0
RAW_ISSUES=0
ISSUE_ROWS=""
if [ "$ISSUES_CODE" = 200 ]; then
  RAW_ISSUES=$(jq 'length' "$ISSUES_BODY" 2>/dev/null || echo 0)
  OPEN_ISSUES=$(jq '[.[] | select(.pull_request == null)] | length' \
    "$ISSUES_BODY" 2>/dev/null || echo 0)
  ISSUE_ROWS=$(jq -r '[.[] | select(.pull_request == null)][] |
    "issue #\(.number)|[\([.labels[].name] | join(",")
      | if . == "" then "none" else . end)] \(.title | gsub("[\\t\\n\\r|]"; " "))"' \
    "$ISSUES_BODY" 2>/dev/null || true)
fi

telemetry_open gitgud:deliver
telemetry_line "default branch" "$DEFAULT_BRANCH"
telemetry_line "current branch" "$CURRENT_BRANCH"
telemetry_line "github auth" "ok (http $AUTH_CODE)"
telemetry_line "uncommitted files" "$CHANGED_FILES"
telemetry_line "staged files" "$STAGED_FILES"
telemetry_line "trunk behind origin" "$BEHIND"
telemetry_line "trunk ahead of origin" "$AHEAD"
telemetry_line "touches .claude/settings.json" "$TOUCHES_SETTINGS"
telemetry_line "guidance" "${GUIDANCE:-none}"

# the drain calls this same file back with a subcommand, so the writer is never a separate tool
telemetry_line "writer" "deliver.sh probe|bucket|update|watch|state (api.github.com)"
telemetry_line "merge method" "$MERGE_METHOD (auto-merge: $AUTO_MERGE, queue: $MERGE_QUEUE)"

# one row per open issue, so the trigger can offer a link and the user can veto it at the gate
if [ "$ISSUES_CODE" != 200 ]; then
  telemetry_line "open issues" "unreadable ($ISSUES_CODE)"
else
  telemetry_line "open issues" "$OPEN_ISSUES"
  if [ "$RAW_ISSUES" -ge 100 ]; then
    telemetry_line "open issues note" "first 100 rows only, so an older issue may be unseen"
  fi
  while IFS='|' read -r ISSUE_KEY ISSUE_VALUE; do
    [ -n "$ISSUE_KEY" ] || continue
    telemetry_line "$ISSUE_KEY" "$ISSUE_VALUE"
  done <<< "$ISSUE_ROWS"
fi

handover_open gitgud:deliver
if [ "$AHEAD" -gt 0 ]; then
  handover_note "$DEFAULT_BRANCH has $AHEAD commit(s) origin does not — resolve before delivering"
elif [ "$CURRENT_BRANCH" = "$DEFAULT_BRANCH" ] && [ "$BEHIND" -eq 0 ] && [ "$STAGED_FILES" -eq 0 ]; then
  handover_note "state is ready — no prep needed before the atomic loop"
else
  # the switch and the fast-forward belong to continue.sh, which the doc's fence already ran
  # this block keeps only what that sidecar has no opinion about, so neither half can drift
  if [ "$CURRENT_BRANCH" != "$DEFAULT_BRANCH" ] || [ "$BEHIND" -gt 0 ]; then
    handover_note "the sync above is continue's; a bucket built off this state waits for it to land"
  fi
  # the drain reads the worktree and never the index, so a staged file is a half-done action the
  # user still owns; clearing it keeps what the api commits and what git reports in agreement
  if [ "$STAGED_FILES" -gt 0 ]; then
    handover_note "run this first; the staged restore is denied, so the line stays yours"
    handover_cmd "git restore --staged :/"
  fi
fi
if [ "$TOUCHES_SETTINGS" = "yes" ]; then
  handover_note "this delivery touches .claude/settings.json — no sandboxed command can write it"
  handover_note "after merging, confirm and restore before pulling:"
  handover_note "git diff origin/$DEFAULT_BRANCH -- .claude/settings.json"
fi
block_close

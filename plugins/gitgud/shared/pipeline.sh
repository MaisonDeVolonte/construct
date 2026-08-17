#!/bin/bash
# ==========================================================
# @file pipeline.sh - writes a bucket to github over the api
# ==========================================================
# @description
# PAIR
# - shared sub-tool for `/gitgud:deliver`; nothing invokes it from a prompt
# - every write is a curl call against api.github.com, the one host the mask injects into
# - the local worktree is never touched: files are read, never staged, moved or reverted
# SHAPE
# - `bucket` turns a file list into one branch, one commit, one pull request, auto-merge armed
# - `watch` polls the required check, then reports whether the pull request actually merged
# - `state` prints the trunk sha and the open pull request count, which callers gate on
# WHY
# - the sandbox cannot push: the mask substitutes on api.github.com bearer headers and nowhere else
# - go binaries never load the sandbox ca, so `gh` fails for a second, unrelated reason
# - a tree api commit is atomic across many files, which a paste of several commands is not
# @see plugins/gitgud/skills/deliver/SKILL.md, plugins/gitgud/shared/handover.sh, README.md

set -euo pipefail

API="https://api.github.com"

die() { echo "fatal: $1" >&2; exit 1; }

command -v curl >/dev/null 2>&1 || die "curl is required"
command -v jq >/dev/null 2>&1 || die "jq is required"
[ -n "${GH_TOKEN:-}" ] || die "GH_TOKEN is not set (see README.md > Settings > Keys)"

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "not a git repository"
ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"

REMOTE_URL=$(git remote get-url origin 2>/dev/null || echo "")
case "$REMOTE_URL" in *github.com*) ;; *) die "origin is not a github remote";; esac
SLUG=$(printf '%s' "$REMOTE_URL" | sed -e 's#^.*github\.com[:/]##' -e 's#\.git$##')

# every call carries the same headers, and every failure prints the api's own message rather than
# a paraphrase, since a 422 body names the field that was wrong
api() {
  local method=$1 path=$2 body=${3:-} out code
  out=$(mktemp "${TMPDIR:-/tmp}/gitgud-api.XXXXXX")
  if [ -n "$body" ]; then
    code=$(curl -sS --max-time 30 -o "$out" -w '%{http_code}' -X "$method" \
      -H "Authorization: Bearer $GH_TOKEN" -H "Accept: application/vnd.github+json" \
      -d "$body" "$API$path" || echo 000)
  else
    code=$(curl -sS --max-time 30 -o "$out" -w '%{http_code}' -X "$method" \
      -H "Authorization: Bearer $GH_TOKEN" -H "Accept: application/vnd.github+json" \
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
    -H "Authorization: Bearer $GH_TOKEN" \
    -d "$(jq -n --arg q "$query" '{query: $q}')" "$API/graphql" || echo 000)
  if [ "$code" != 200 ]; then
    echo "graphql failed (http $code)" >&2; cat "$out" >&2; rm -f "$out"; return 1; fi
  cat "$out"; rm -f "$out"
}

trunk_sha() { api GET "/repos/$SLUG/git/ref/heads/$1" | jq -r '.object.sha'; }

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

# one branch and one commit carrying every path; the caller owns the ordering between buckets
cmd_bucket() {
  local base=$1 branch=$2 title=$3 bodyfile=$4; shift 4
  [ $# -gt 0 ] || die "bucket needs at least one path"
  [ -f "$bodyfile" ] || die "no commit body file at $bodyfile"

  local basesha basetree entries treesha commitsha body prnum prid
  basesha=$(trunk_sha "$base")
  basetree=$(api GET "/repos/$SLUG/git/commits/$basesha" | jq -r '.tree.sha')

  entries='[]'
  local path
  for path in "$@"; do
    entries=$(printf '%s\n%s' "$entries" "$(tree_entry "$path")" \
      | jq -s '.[0] + [.[1]]')
  done

  treesha=$(api POST "/repos/$SLUG/git/trees" \
    "$(jq -n --arg b "$basetree" --argjson t "$entries" '{base_tree: $b, tree: $t}')" \
    | jq -r '.sha')

  body=$(cat "$bodyfile")
  commitsha=$(api POST "/repos/$SLUG/git/commits" \
    "$(jq -n --arg m "$title

$body" --arg t "$treesha" --arg p "$basesha" '{message: $m, tree: $t, parents: [$p]}')" \
    | jq -r '.sha')

  api POST "/repos/$SLUG/git/refs" \
    "$(jq -n --arg r "refs/heads/$branch" --arg s "$commitsha" '{ref: $r, sha: $s}')" >/dev/null

  prnum=$(api POST "/repos/$SLUG/pulls" \
    "$(jq -n --arg t "$title" --arg h "$branch" --arg b "$base" --arg d "$body" \
      '{title: $t, head: $h, base: $b, body: $d}')" | jq -r '.number')

  prid=$(api GET "/repos/$SLUG/pulls/$prnum" | jq -r '.node_id')
  local armed=yes
  graphql "mutation { enablePullRequestAutoMerge(input: {pullRequestId: \"$prid\", mergeMethod: REBASE}) { clientMutationId } }" \
    | jq -e '.errors | not' >/dev/null 2>&1 || armed=no

  printf 'branch: %s\ncommit: %s\npr: %s\nauto-merge: %s\nfiles: %s\n' \
    "$branch" "${commitsha:0:7}" "$prnum" "$armed" "$#"
}

# the required check decides whether a pull request may merge, so this waits on the check first
# and reports the merge second; a caller that skips the wait races the next bucket's base sha
cmd_watch() {
  local prnum=$1 tries=${2:-60} pr sha status conclusion merged
  local n=0
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
    fi
    n=$((n + 1))
    sleep 5
  done
  printf 'pr: %s\nchecks: %s\nmerged: no\n' "$prnum" "${conclusion:-timeout}"
  return 1
}

cmd_state() {
  local base=${1:-main}
  printf 'repo: %s\ntrunk: %s\ntrunk sha: %s\nopen prs: %s\n' \
    "$SLUG" "$base" "$(trunk_sha "$base" | cut -c1-7)" \
    "$(api GET "/repos/$SLUG/pulls?state=open&per_page=100" | jq 'length')"
}

case "${1:-}" in
  bucket) shift; cmd_bucket "$@";;
  watch)  shift; cmd_watch "$@";;
  state)  shift; cmd_state "$@";;
  *) die "usage: pipeline.sh bucket <base> <branch> <title> <bodyfile> <path>... | watch <pr> [tries] | state [base]";;
esac

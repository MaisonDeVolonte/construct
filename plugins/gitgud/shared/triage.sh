#!/bin/bash
# ===================================================
# @file triage.sh - read-only git diagnostics sidecar
# ===================================================
# @description
# PAIR
# - sidecar for `/gitgud:audit` — probes repo and branch state, and reports it as telemetry
# - read-only and run only on the explicit command; it never mutates a tracked file
# - team probes ride curl + bearer against the github rest api, the one path the sandbox serves
# - `/gitgud:prune` and `/gitgud:nuke` both call it, since branch triage is one read for all three
# TRIGGER
# - the doc labels ghost branches, local clutter, rebase-absorbed branches, and conflict risk
# - `merged` is a patch-id read and `absorbed` is a tree read, so only `absorbed` clears a rebase
# - it outputs a numbered issue list, each with a manual command and an `@agent` shortcut
# - it then appends that report to `.operator/git/YYYY-MM-DD.md`, in the `/operator:settings` shape
# - the sidecar names today's audit path and count, and never creates the file itself
# @see plugins/gitgud/skills/audit/SKILL.md, /operator:settings, plugins/gitgud/shared/handover.sh, tools/check-skills/README.md, .operator/

set -euo pipefail

# probes: echo "key: $(git some command 2>/dev/null || echo n/a)"

# this file is library code rather than a sidecar, so handover sits beside it, not two levels up
SHARED=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)
if [ ! -f "$SHARED/handover.sh" ]; then
  echo "fatal: no plugins/gitgud/shared/handover.sh reachable from this library" >&2; exit 1; fi
# shellcheck source=./handover.sh
. "$SHARED/handover.sh"

require_repo

# setup: targets the default remote branch, falling back when origin/HEAD is missing
# prunes stale tracking refs so the branch loop below reads the real remote state
DEFAULT_BRANCH=$(git_default_branch)
DEFAULT_BRANCH=${DEFAULT_BRANCH:-main}
CURRENT_BRANCH=$(git_current_branch)
PROTECTED="$DEFAULT_BRANCH|production"
git fetch --prune origin >/dev/null 2>&1 || true

# audit: one file per day, many audits per file — reported never created, since /gitgud:prune runs
# this sidecar for branch classification alone; paths anchor to the repo root, not the caller's dir
echo "--- audit ---"
ROOT=$(git rev-parse --show-toplevel)
# the kind in the name keeps two triggers writing the same day out of one interleaved file
TODAYS_AUDIT=".operator/git/$(date +%Y-%m-%d).md"
# no file yet means no audits yet, which is the count the agent numbers its first one from
if [ -f "$ROOT/$TODAYS_AUDIT" ];
then AUDIT_COUNT=$(grep -c '^## Git Audit #' "$ROOT/$TODAYS_AUDIT" || true)
else AUDIT_COUNT=0; fi
echo "audit_file: $TODAYS_AUDIT"
echo "audit_time: $(date '+%Y-%m-%d %H:%M')"
echo "audit_count: $AUDIT_COUNT"


# local: current branch, last activity, staged/unstaged/untracked files, hidden stashes
echo "--- local ---"
echo "current_branch: ${CURRENT_BRANCH:-detached}"
echo "last_activity: $(git log -1 --format='%cr' 2>/dev/null || echo n/a)"
echo "staged_files: $(git diff --cached --name-only | wc -l | tr -d ' ')"
echo "unstaged_files: $(git diff --name-only | wc -l | tr -d ' ')"
echo "untracked_files: $(git ls-files --others --exclude-standard | wc -l | tr -d ' ')"
echo "hidden_stashes: $(git stash list | wc -l | tr -d ' ')"
echo "index_locked: $([ -f .git/index.lock ] && echo yes || echo no)"
echo "is_detached: $([ -n "$CURRENT_BRANCH" ] && echo no || echo yes)"
echo "local_branches: $(git for-each-ref --format='%(refname:short)' refs/heads/ | grep -vx "$DEFAULT_BRANCH" | paste -sd, - | sed 's/,/, /g' || echo none)"

# origin: default branch ahead/behind, unpushed/incoming commits, conflict risk files
echo "--- origin ---"
read -r DA DB <<< "$(git rev-list --left-right --count "$DEFAULT_BRANCH...origin/$DEFAULT_BRANCH" 2>/dev/null || echo '0 0')"
echo "default_ahead: ${DA:-0}"
echo "default_behind: ${DB:-0}"
echo "branch_behind_default: $(git rev-list --count "HEAD..origin/$DEFAULT_BRANCH" 2>/dev/null || echo n/a)"
echo "unpushed_commits: $(git rev-list --count '@{u}..HEAD' 2>/dev/null || echo n/a)"
echo "incoming_commits: $(git rev-list --count 'HEAD..@{u}' 2>/dev/null || echo n/a)"
echo "dependency_changes: $(git diff --name-only "origin/$DEFAULT_BRANCH...HEAD" -- package.json package-lock.json yarn.lock pnpm-lock.yaml bun.lockb 2>/dev/null | wc -l | tr -d ' ')"
FORK=$(git merge-base HEAD "origin/$DEFAULT_BRANCH" 2>/dev/null)
if [ -n "$FORK" ]; then
  DIFF_HEAD=$(git diff --name-only "$FORK" HEAD 2>/dev/null)
  DIFF_ORIGIN=$(git diff --name-only "$FORK" "origin/$DEFAULT_BRANCH" 2>/dev/null)
  
  if [ -n "$DIFF_HEAD" ] && [ -n "$DIFF_ORIGIN" ]; then
    COUNT=$(echo "$DIFF_HEAD" | grep -F -x "$DIFF_ORIGIN" | wc -l | tr -d ' ')
  else
    COUNT=0
  fi
  echo "conflict_risk_files: $COUNT"
else echo "conflict_risk_files: n/a"; fi

# team: last build, active PRs, review PRs, assigned issues
# probed through curl + the rest api since gh cannot verify tls from inside the sandbox
echo "--- team ---"
GITHUB_API="https://api.github.com"

# owner/repo parsed from the origin url, handling https and ssh shapes alike
REPO_SLUG=$(git remote get-url origin 2>/dev/null | grep 'github\.com' | sed -e 's#^.*github\.com[:/]##' -e 's#\.git$##')

# bearer auth is the one shape the mask proxy can substitute; basic auth would base64 the
# sentinel out of its reach (see README.md > Settings > Keys > GitHub)
github_api() {
  curl -sS --max-time 15 \
    -H "Authorization: Bearer $GH_TOKEN" \
    -H "Accept: application/vnd.github+json" \
    "$@"
}

# probes only run when the token, the tools, and the remote all resolve; login doubles as "me"
GH_LOGIN=""
if [ -n "${GH_TOKEN:-}" ] && [ -n "$REPO_SLUG" ] && command -v curl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
  GH_LOGIN=$(github_api "$GITHUB_API/user" 2>/dev/null | jq -r '.login // empty' 2>/dev/null)
fi

if [ -n "$GH_LOGIN" ]; then
  # newest workflow run on this branch: "completed success", "in_progress pending", or none
  echo "last_build: $(github_api "$GITHUB_API/repos/$REPO_SLUG/actions/runs?branch=$CURRENT_BRANCH&per_page=1" 2>/dev/null \
    | jq -r 'if .workflow_runs[0] then "\(.workflow_runs[0].status) \(.workflow_runs[0].conclusion // "pending")" else "none" end' 2>/dev/null || echo n/a)"

  # one fetch of the open prs feeds both counts below
  OPEN_PRS=$(github_api "$GITHUB_API/repos/$REPO_SLUG/pulls?state=open&per_page=100" 2>/dev/null || echo '[]')
  echo "active_prs: $(echo "$OPEN_PRS" | jq --arg me "$GH_LOGIN" '[.[] | select(.user.login == $me)] | length' 2>/dev/null || echo n/a)"
  echo "review_prs: $(echo "$OPEN_PRS" | jq --arg me "$GH_LOGIN" '[.[] | select(any(.requested_reviewers[]?; .login == $me))] | length' 2>/dev/null || echo n/a)"

  # the issues endpoint returns prs too, so drop anything carrying a pull_request stub
  echo "assigned_issues: $(github_api "$GITHUB_API/repos/$REPO_SLUG/issues?state=open&assignee=$GH_LOGIN&per_page=100" 2>/dev/null \
    | jq '[.[] | select(.pull_request == null)] | length' 2>/dev/null || echo n/a)"
else echo "github: api unavailable (team probes skipped)"; fi

# is_absorbed now lives in handover.sh, since /gitgud:prune needs the same deletion gate

# branches: last commit, ahead/behind, upstream tracking, reachable, remote, merged, absorbed
echo "--- branches ---"
for branch in $(git for-each-ref --sort=-committerdate --format='%(refname:short)' refs/heads/ | grep -vx "$DEFAULT_BRANCH"); do
  B_LAST=$(git log -1 --format='%cr' "$branch" 2>/dev/null || echo n/a)
  B_AHEAD=$(git rev-list --count "$DEFAULT_BRANCH..$branch" 2>/dev/null || echo '?')
  B_TRACK=$(git for-each-ref --format='%(upstream:track,nobracket)' "refs/heads/$branch")
  B_BEHIND=$(git rev-list --count "$branch..$DEFAULT_BRANCH" 2>/dev/null || echo '?')
  if git merge-base --is-ancestor "$branch" "$DEFAULT_BRANCH" 2>/dev/null; then B_REACHABLE=yes; else B_REACHABLE=no; fi
  if git rev-parse --verify --quiet "refs/remotes/origin/$branch" >/dev/null; then B_REMOTE=yes; else B_REMOTE=no; fi
  if [ -n "$(git cherry "$DEFAULT_BRANCH" "$branch" 2>/dev/null | grep '^+')" ]; then B_MERGED=no; else B_MERGED=yes; fi
  # against origin, not local: absorbed answers "is work lost by deleting", and a stale local
  # trunk reads a landed branch as unmerged; the fetch above keeps this baseline current
  B_ABSORBED=$(is_absorbed "origin/$DEFAULT_BRANCH" "$branch")
  echo "branch: $branch | last: $B_LAST | ahead: $B_AHEAD | behind: $B_BEHIND | upstream: ${B_TRACK:-none} | reachable: $B_REACHABLE | remote: $B_REMOTE | merged: $B_MERGED | absorbed: $B_ABSORBED | last_commit: $(git log -1 --format='%s' "$branch" 2>/dev/null)"
done

# remote-only: branches on origin with no local counterpart, never reported by the loop above
echo "--- remote-only ---"
for branch in $(git for-each-ref --sort=-committerdate --format='%(refname)' refs/remotes/origin/ | sed 's@^refs/remotes/origin/@@' | grep -vx HEAD | grep -vxE "$PROTECTED"); do
  git show-ref --verify --quiet "refs/heads/$branch" && continue
  R_LAST=$(git log -1 --format='%cr' "origin/$branch" 2>/dev/null || echo n/a)
  R_AHEAD=$(git rev-list --count "origin/$DEFAULT_BRANCH..origin/$branch" 2>/dev/null || echo '?')
  if git merge-base --is-ancestor "origin/$branch" "origin/$DEFAULT_BRANCH" 2>/dev/null; then R_REACHABLE=yes; else R_REACHABLE=no; fi
  if [ -n "$(git cherry "origin/$DEFAULT_BRANCH" "origin/$branch" 2>/dev/null | grep '^+')" ]; then R_MERGED=no; else R_MERGED=yes; fi
  R_ABSORBED=$(is_absorbed "origin/$DEFAULT_BRANCH" "origin/$branch")
  echo "remote_branch: $branch | last: $R_LAST | ahead: $R_AHEAD | reachable: $R_REACHABLE | merged: $R_MERGED | absorbed: $R_ABSORBED | last_commit: $(git log -1 --format='%s' "origin/$branch" 2>/dev/null)"
done

echo "--- end ---"

# ==============
# ARTIFACT
#   this skill's own dated artifact, graded here so nothing outside this file decides its shape.
#   the shape lives in this skill's SKILL.md and the labels below are what this sidecar emits
# ==============
ARTIFACT_KIND="git"
ARTIFACT_SECTIONS=$'state\nfindings\nresolutions\ntelemetry'
ARTIFACT_LABELS='Ghost Branch|Local Clutter|Rebase Absorbed|Conflict Risk|Dirty Trunk|Uncommitted Tree'
ARTIFACT_MAX_WIDTH=100

# this library prints telemetry rather than collecting findings, so the two adapt to that
artifact_err()  { echo "artifact_ERROR: $1:$2 $3 — $4"; }
artifact_warn() { echo "artifact_WARN:  $1:$2 $3 — $4"; }

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

check_artifact ".operator/git"

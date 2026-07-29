#!/bin/bash
# =====================================================
# @file gitaudit.sh - read-only git diagnostics sidecar
# =====================================================
# @description
# - sidecar for `@gitaudit` — probes repo/branch state for telemetry
# - seeds today's audit file and reports its path, so the agent appends to a known target
# @see AGENTS.md, AGENTS/templates/git.md, AGENTS/git/gitaudit.md, AGENTS/templates/audits.md, docs/audits/

# probes: echo "key: $(git some command 2>/dev/null || echo n/a)"

# check if in git repository, aborts if not
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
echo "FATAL ERROR: Not a git repository (or any of the parent directories)" >&2; exit 1; fi

# setup: targets default remote branch, handles fallback naming, prunes stale tracking refs across all networks
git remote set-head origin --auto >/dev/null 2>&1 || true
DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
DEFAULT_BRANCH=${DEFAULT_BRANCH:-main}
CURRENT_BRANCH=$(git branch --show-current)
PROTECTED="$DEFAULT_BRANCH|production"
git fetch --prune origin >/dev/null 2>&1 || true

# audit: one file per day, many audits per file — seeded here so the agent has a known target;
# paths anchor to the repo root, since the sidecar can be invoked from any subdirectory
echo "--- audit ---"
ROOT=$(git rev-parse --show-toplevel)
TODAYS_AUDIT="docs/audits/$(date +%Y-%m-%d).md"
if [ ! -f "$ROOT/$TODAYS_AUDIT" ];
then mkdir -p "$ROOT/docs/audits"; echo "# $TODAYS_AUDIT" > "$ROOT/$TODAYS_AUDIT"; fi
echo "audit_file: $TODAYS_AUDIT"
echo "audit_time: $(date '+%Y-%m-%d %H:%M')"
echo "audit_count: $(grep -c '^## Audit #' "$ROOT/$TODAYS_AUDIT" 2>/dev/null || true)"

# local: current branch, last activity, staged/unstaged/untracked files, hidden stashes
echo "--- local ---"
echo "current_branch: ${CURRENT_BRANCH:-detached}"
echo "last_activity: $(git log -1 --format='%cr' 2>/dev/null || echo n/a)"
echo "staged_files: $(git diff --cached --name-only | wc -l | tr -d ' ')"
echo "unstaged_files: $(git diff --name-only | wc -l | tr -d ' ')"
echo "untracked_files: $(git ls-files --others --exclude-standard | wc -l | tr -d ' ')"
echo "hidden_stashes: $(git stash list | wc -l | tr -d ' ')"
echo "index_locked: $([ -f .git/index.lock ] && echo yes || echo no)"
echo "is_detached: $(git symbolic-ref -q HEAD >/dev/null && echo no || echo yes)"
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
echo "--- team ---"
if gh auth status >/dev/null 2>&1; then
  echo "last_build: $(gh run list --branch "$CURRENT_BRANCH" --limit 1 --json status,conclusion -q '.[0] | "\(.status) \(.conclusion)"' 2>/dev/null || echo none)"
  echo "active_prs: $(gh pr list --author '@me' 2>/dev/null | wc -l | tr -d ' ')"
  echo "review_prs: $(gh pr list --search 'review-requested:@me' 2>/dev/null | wc -l | tr -d ' ')"
  echo "assigned_issues: $(gh issue list --assignee '@me' 2>/dev/null | wc -l | tr -d ' ')"
else echo "github: gh unavailable (team probes skipped)"; fi

# branches: last commit, ahead/behind, upstream tracking, reachable, remote, merged status
echo "--- branches ---"
for branch in $(git for-each-ref --sort=-committerdate --format='%(refname:short)' refs/heads/ | grep -vx "$DEFAULT_BRANCH"); do
  B_LAST=$(git log -1 --format='%cr' "$branch" 2>/dev/null || echo n/a)
  B_AHEAD=$(git rev-list --count "$DEFAULT_BRANCH..$branch" 2>/dev/null || echo '?')
  B_TRACK=$(git for-each-ref --format='%(upstream:track,nobracket)' "refs/heads/$branch")
  B_BEHIND=$(git rev-list --count "$branch..$DEFAULT_BRANCH" 2>/dev/null || echo '?')
  if git merge-base --is-ancestor "$branch" "$DEFAULT_BRANCH" 2>/dev/null; then B_REACHABLE=yes; else B_REACHABLE=no; fi
  if git rev-parse --verify --quiet "refs/remotes/origin/$branch" >/dev/null; then B_REMOTE=yes; else B_REMOTE=no; fi
  if git cherry "$DEFAULT_BRANCH" "$branch" 2>/dev/null | grep -q '^+'; then B_MERGED=no; else B_MERGED=yes; fi
  echo "branch: $branch | last: $B_LAST | ahead: $B_AHEAD | behind: $B_BEHIND | upstream: ${B_TRACK:-none} | reachable: $B_REACHABLE | remote: $B_REMOTE | merged: $B_MERGED | last_commit: $(git log -1 --format='%s' "$branch" 2>/dev/null)"
done

# remote-only: branches on origin with no local counterpart, never reported by the loop above
echo "--- remote-only ---"
for branch in $(git for-each-ref --sort=-committerdate --format='%(refname)' refs/remotes/origin/ | sed 's@^refs/remotes/origin/@@' | grep -vx HEAD | grep -vxE "$PROTECTED"); do
  git show-ref --verify --quiet "refs/heads/$branch" && continue
  R_LAST=$(git log -1 --format='%cr' "origin/$branch" 2>/dev/null || echo n/a)
  R_AHEAD=$(git rev-list --count "origin/$DEFAULT_BRANCH..origin/$branch" 2>/dev/null || echo '?')
  if git merge-base --is-ancestor "origin/$branch" "origin/$DEFAULT_BRANCH" 2>/dev/null; then R_REACHABLE=yes; else R_REACHABLE=no; fi
  if git cherry "origin/$DEFAULT_BRANCH" "origin/$branch" 2>/dev/null | grep -q '^+'; then R_MERGED=no; else R_MERGED=yes; fi
  echo "remote_branch: $branch | last: $R_LAST | ahead: $R_AHEAD | reachable: $R_REACHABLE | merged: $R_MERGED | last_commit: $(git log -1 --format='%s' "origin/$branch" 2>/dev/null)"
done

echo "--- end ---"

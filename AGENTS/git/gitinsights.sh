#!/bin/bash
# ===============================================
# @file gitinsights.sh - opportunity-scan sidecar
# ===============================================
# @description
# - sidecar for `@gitinsights` — deterministic checks for broken refs and code markers
# - one of three streams the trigger merges; reconciliation and the logs carry the judgement
# - report-only by contract: it exits 0 on findings, since a lead is not a failure
# - reports today's insights path and report count, and never creates the file itself
# - `--keep` preserves the tmp/ scratch file, which a failed run preserves anyway
# @see AGENTS.md, AGENTS/templates/git.md, AGENTS/git/gitinsights.md, AGENTS/templates/insights.md, docs/insights/

set -euo pipefail

# ==============
# PREFLIGHT
# ==============
# local, read-only scan — no gh/network needed, only a git repo to anchor paths against
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "fatal: not a git repository" >&2; exit 1; fi

# scan from the repo root so every reference resolves regardless of the invocation dir
cd "$(git rev-parse --show-toplevel)"

# one file per day, many reports per file — reported never created, so a ci scan leaves nothing
# the cd above already anchored us to the repo root, so these paths stay relative
TODAYS_INSIGHTS="docs/insights/$(date +%Y-%m-%d).md"
INSIGHTS_TIME=$(date '+%Y-%m-%d %H:%M')
# no file yet means no reports yet, which is the count the agent numbers its first one from
if [ -f "$TODAYS_INSIGHTS" ];
then INSIGHTS_COUNT=$(grep -c '^## Insight #' "$TODAYS_INSIGHTS" || true)
else INSIGHTS_COUNT=0; fi

KEEP=0
for arg in "$@"; do
  if [ "$arg" = "--keep" ]; then KEEP=1; fi
done

# repo-local scratch: the sandbox denies writes outside cwd, and macos mktemp ignores TMPDIR
TMPROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)/tmp"
TMPTAG=$(basename "${BASH_SOURCE[0]}" .sh)
mkdir -p "$TMPROOT"

# findings collect here as "category: detail" lines; this is report-only, so the run never fails
FINDINGS=$(mktemp "$TMPROOT/$TMPTAG-findings.XXXXXX")
# a failed run leaves scratch behind to read; --keep does the same after a clean one
cleanup() { st=$?; if [ "$KEEP" -eq 0 ] && [ "$st" -eq 0 ]; then rm -f "$FINDINGS"; fi; }
trap cleanup EXIT

# dirs never worth scanning: dependencies, build output, and generated code
EXCLUDES=(--exclude-dir=node_modules --exclude-dir=.git --exclude-dir=.next --exclude-dir=.open-next --exclude-dir=webflow --exclude-dir=report --exclude-dir=results --exclude='*.generated.*')

# reference targets generated at build/test time (not committed source) — never flag as missing
is_generated() {
  case "$1" in
    *tests/report*|*tests/results*|*.next*|*node_modules*) return 0;;
    # runtime artifact dirs: gitignored and written on demand, so absent from a fresh clone
    docs/logs*|docs/plans*|docs/study*|docs/audits*|docs/brutal*|docs/insights*|docs/graphs*) return 0;;
    *) return 1;;
  esac
}

# reference targets that live in the host project, not this repo — AGENTS.md is a per-project
# symlink and the harness/build configs belong to whatever project the agent is running in
is_host_only() {
  case "$1" in
    AGENTS.md) return 0;;
    .claude|.claude/*|.grok|.grok/*) return 0;;
    eslint.config.mjs) return 0;;
    # a host project's deploy pipeline; named exactly so a broken ci.yml ref still gets caught
    .github/workflows/deploy.yml) return 0;;
    *) return 1;;
  esac
}

# ==============
# DETERMINISTIC CHECKS
#   each check greps the tree and appends "category: detail" lines to $FINDINGS
#   to add a check (e.g. import-path resolution): write a function, then call it in the run list
# ==============

# mirror-pointer directives must resolve — anchored to real directive lines (leading // or #),
# never prose that merely describes the convention
check_mirror_pointers() {
  local hits file target
  hits=$(grep -rInE '^[[:space:]]*(//|#)[[:space:]]*@mirror[[:space:]]+' \
    --include='*.md' --include='*.sh' --include='*.ts' --include='*.tsx' "${EXCLUDES[@]}" . 2>/dev/null || true)
  while IFS= read -r hit; do
    [ -z "$hit" ] && continue
    file=${hit%%:*}
    target=$(printf '%s' "$hit" | sed -n 's/.*@mirror[[:space:]]\{1,\}\([^[:space:]]\{1,\}\).*/\1/p')
    [ -z "$target" ] && continue
    case "$target" in */*|*.*) ;; *) continue;; esac   # only real path-shaped targets, not prose words
    [ -e "$target" ] && continue
    echo "broken_mirror: $file -> $target" >> "$FINDINGS"
  done <<< "$hits"
}

# markdown links must resolve — skip external urls and in-page anchors, resolve the rest
# relative to the file that contains them
check_markdown_links() {
  local hits file dir target resolved
  hits=$(grep -rInoE '\]\([^)]+\)' --include='*.md' "${EXCLUDES[@]}" . 2>/dev/null || true)
  while IFS= read -r hit; do
    [ -z "$hit" ] && continue
    file=${hit%%:*}
    target=$(printf '%s' "$hit" | sed -n 's/.*](\([^)]*\)).*/\1/p')
    [ -z "$target" ] && continue
    case "$target" in
      http://*|https://*|mailto:*|\#*) continue;;
    esac
    target=${target%%#*}                    # drop any #anchor suffix
    [ -z "$target" ] && continue
    dir=$(dirname "$file")
    case "$target" in
      /*) resolved=".${target}";;           # leading slash = repo root
      *)  resolved="${dir}/${target}";;     # otherwise relative to the file
    esac
    is_generated "$resolved" && continue
    [ -e "$resolved" ] && continue
    echo "broken_link: $file -> $target" >> "$FINDINGS"
  done <<< "$hits"
}

# see-tag header paths must resolve — comma-separated, repo-root-relative, sometimes dir-style
# with a trailing slash; skip {@link ...} url forms
# anchored to a real header line (leading #, *, or //) so the pattern can't match its own
# definition, nor the grep flags on any line that merely mentions the tag
check_see_paths() {
  local hits file paths token ref
  hits=$(grep -rInE '^[[:space:]]*(#|\*|//)[[:space:]]*@see[[:space:]]' \
    --include='*.ts' --include='*.tsx' --include='*.mjs' --include='*.js' --include='*.css' \
    --include='*.sh' --include='*.md' "${EXCLUDES[@]}" . 2>/dev/null || true)
  while IFS= read -r hit; do
    [ -z "$hit" ] && continue
    file=${hit%%:*}
    paths=$(printf '%s' "$hit" | sed -n 's/.*@see[[:space:]]\{1,\}\(.*\)/\1/p')
    [ -z "$paths" ] && continue
    case "$paths" in *"{@link"*|*http*) continue;; esac   # a linked url, not a path list
    for token in $(printf '%s' "$paths" | tr ',' ' '); do
      ref=${token#/}                        # strip leading slash (repo root)
      ref=${ref%/}                          # strip trailing slash (dir style)
      [ -z "$ref" ] && continue
      case "$ref" in */*|*.*) ;; *) continue;; esac   # skip bare prose words, keep path-shaped refs
      is_generated "$ref" && continue
      is_host_only "$ref" && continue
      [ -e "$ref" ] && continue
      echo "broken_see: $file -> $token" >> "$FINDINGS"
    done
  done <<< "$hits"
}

# standing code markers (todo/fixme/hack) aren't broken references — they're logged as leads;
# anchored to a comment opener so the pattern can't match its own definition
check_code_markers() {
  local hits
  hits=$(grep -rInE '(#|//|/\*)[[:space:]]*(TODO|FIXME|HACK)' \
    --include='*.ts' --include='*.tsx' --include='*.css' --include='*.mjs' \
    --include='*.sh' --include='*.md' "${EXCLUDES[@]}" . 2>/dev/null || true)
  while IFS= read -r hit; do
    [ -z "$hit" ] && continue
    echo "marker: $hit" >> "$FINDINGS"
  done <<< "$hits"
}

# --- run list (add new checks here) ---
check_mirror_pointers
check_markdown_links
check_see_paths
check_code_markers

# ==============
# TELEMETRY
# ==============
broken_mirror=$(grep -c '^broken_mirror:' "$FINDINGS" || true)
broken_link=$(grep -c '^broken_link:' "$FINDINGS" || true)
broken_see=$(grep -c '^broken_see:' "$FINDINGS" || true)
markers=$(grep -c '^marker:' "$FINDINGS" || true)
total=$(grep -c . "$FINDINGS" || true)

cat <<EOF

=== @gitinsights sidecar ===
insights_file: $TODAYS_INSIGHTS
insights_time: $INSIGHTS_TIME
insights_count: $INSIGHTS_COUNT
SCANNED: mirror pointers, markdown links, see-tag paths, code markers
broken_mirror: $broken_mirror
broken_link: $broken_link
broken_see: $broken_see
markers: $markers
total: $total
--- findings ---
EOF

if [ "$total" -eq 0 ]; then
  echo "none — every scanned reference resolves"
else
  sort "$FINDINGS"
fi

echo "=========================="

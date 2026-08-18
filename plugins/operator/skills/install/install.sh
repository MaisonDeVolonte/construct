#!/bin/bash
# ==============================================================
# @file install.sh - machine-wide plugin install inventory sidecar
# ==============================================================
# @description
# PAIR
# - sidecar for `/operator:install` — reports every marketplace, plugin and skill on this machine
# - it answers one question: what is installed, at which path, and which copy actually wins
# - a plugin can be present three ways at once, and only one of them reaches a session
# SOURCE
# - `known_marketplaces.json` names each catalogue and the clone it was fetched into
# - `installed_plugins.json` names each install, its version, its scope and the project that asked
# - `cache/<marketplace>/<plugin>/<version>/` is the copy on disk, which the two above only point at
# - `~/.claude/skills/<name>/` is a skills-dir plugin, loaded by directory rather than by install
# - `enabledPlugins` across the settings scopes decides which of those names a session may claim
# - reads files rather than shelling out to `claude plugin list`, so a broken install still reports
# RUN
# - read-only: it measures and reports, and every install or removal is the user's to run
# - `--quick` reports inline and writes nothing; `--strict` promotes warnings; `--keep` holds tmp
# - exits 1 on any error, so a dangling symlink fails a ci run rather than reading as a clean one
# @see plugins/operator/skills/install/SKILL.md, plugins/operator/skills/setup/setup.sh, README.md

set -euo pipefail

# the doc is read only after this has already run, so help is refused here or not at all; the doc's
# own '## Help' section owns the output, which is why this prints a marker rather than a usage text
case " $* " in *" --help "*|*" -h "*) echo "help: requested"; exit 0;; esac

# the smoke case proves this file parses and its guards return; /test-skills reads the sources,
# the @see paths and the tool guards statically, so nothing here runs a step of the skill
case " $* " in *" --test "*) echo "test: ok"; exit 0;; esac

# ==============
# PREFLIGHT
# ==============
command -v jq >/dev/null 2>&1 || { echo "fatal: jq is required" >&2; exit 1; }

QUICK=0
STRICT=0
KEEP=0
for arg in "$@"; do
  case "$arg" in
    --quick) QUICK=1;;
    --strict) STRICT=1;;
    --keep) KEEP=1;;
    *) echo "fatal: unknown flag $arg" >&2; exit 1;;
  esac
done

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "fatal: not a git repository" >&2; exit 1; fi
ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"

PLUGINS="$HOME/.claude/plugins"
MARKETS="$PLUGINS/known_marketplaces.json"
INSTALLED="$PLUGINS/installed_plugins.json"
CACHE="$PLUGINS/cache"
SKILLSDIR="$HOME/.claude/skills"
TILDE='~'

# repo-local scratch: the sandbox denies writes outside cwd, and macos mktemp ignores TMPDIR
TMPROOT="$ROOT/tmp"
TMPTAG=$(basename "${BASH_SOURCE[0]}" .sh)
mkdir -p "$TMPROOT"
FINDINGS=$(mktemp "$TMPROOT/$TMPTAG-findings.XXXXXX")
SCRATCH=$(mktemp -d "$TMPROOT/$TMPTAG-scratch.XXXXXX")
# a failed run leaves scratch behind to read; a clean run sweeps every stale pair unless kept
cleanup() { st=$?; if [ "$KEEP" -eq 0 ] && [ "$st" -eq 0 ]; then bash "${TMPROOT%/tmp}/plugins/operator/shared/clean-tmp.sh" "$TMPTAG"; fi; }
trap cleanup EXIT

# a finding leads with its kind rather than its plugin, so the artifact stays greppable by kind
# and two plugins shadowed the same way sort together instead of by alphabet
err()  { printf 'ERROR|%s|%s|%s\n' "$1" "$2" "$3" >> "$FINDINGS"; }
warn() { printf 'WARN|%s|%s|%s\n'  "$1" "$2" "$3" >> "$FINDINGS"; }

mask() { printf '%s' "${1/#$HOME/$TILDE}"; }

# a directory that does not exist reads as 0 rather than as an error: a machine with no cache at
# all is a legitimate state, and sizing it is never the thing that should end the run
size_of() {
  [ -e "$1" ] || { printf '0'; return; }
  du -sk "$1" 2>/dev/null | awk '{ print $1 + 0 }'
}

human() {
  awk -v k="$1" 'BEGIN { if (k >= 1024) printf "%.1fM", k / 1024; else printf "%dK", k }'
}

# ==============
# MARKETPLACES
#   the catalogue layer: what this machine trusts, and where each catalogue was cloned to
# ==============
: > "$SCRATCH/markets"
if [ -f "$MARKETS" ]; then
  jq -r 'to_entries[]
    | [ .key,
        (.value.source.source // "?"),
        (.value.source.repo // .value.source.path // .value.source.url // "?"),
        (.value.source.ref // "-"),
        (.value.installLocation // "-"),
        ((.value.autoUpdate // false) | tostring) ] | @tsv' "$MARKETS" \
    > "$SCRATCH/markets" 2>/dev/null || {
      err unreadable known_marketplaces "the file exists but jq could not parse it"; }
else
  warn absent known_marketplaces "no catalogue file, so no marketplace install is possible here"
fi

MARKET_COUNT=$(wc -l < "$SCRATCH/markets" | tr -d ' ')

# a catalogue whose clone is gone cannot answer an install or an update, and the entry survives
# the deletion, so the drift is invisible until the next install fails
while IFS=$'\t' read -r name _src _repo _ref location _auto; do
  [ -n "${name:-}" ] || continue
  [ "$location" = "-" ] && continue
  [ -d "$location" ] || err missing_clone "$name" "the entry names $(mask "$location"), which is gone"
done < "$SCRATCH/markets"

# ==============
# INSTALLS
#   the registry layer: one row per install, which is what a session resolves a plugin name through
# ==============
: > "$SCRATCH/installs"
if [ -f "$INSTALLED" ]; then
  jq -r '.plugins // {} | to_entries[] | .key as $id | .value[]
    | [ $id,
        (.version // "?"),
        (.scope // "?"),
        (.projectPath // "-"),
        (.installPath // "-"),
        ((.auto // false) | tostring) ] | @tsv' "$INSTALLED" \
    > "$SCRATCH/installs" 2>/dev/null || {
      err unreadable installed_plugins "the file exists but jq could not parse it"; }
else
  warn absent installed_plugins "no registry file, so nothing is installed through a marketplace"
fi

INSTALL_COUNT=$(wc -l < "$SCRATCH/installs" | tr -d ' ')

# the registry points at a directory; a row whose directory is gone resolves to nothing, and the
# session reports the plugin as failed rather than as absent, which reads as a different fault
while IFS=$'\t' read -r id version _scope _project path _auto; do
  [ -n "${id:-}" ] || continue
  [ "$path" = "-" ] && continue
  [ -d "$path" ] || err missing_install "$id" "$version is registered at a path that is gone"
done < "$SCRATCH/installs"

# the same plugin installed for two projects is not a fault, and it is the shape that produces a
# stale copy nobody notices, so it is named once per plugin rather than once per row
awk -F'\t' '{ print $1 }' "$SCRATCH/installs" | sort | uniq -c \
  | awk '$1 > 1 { print $2 "\t" $1 }' > "$SCRATCH/dupes"
while IFS=$'\t' read -r id count; do
  [ -n "${id:-}" ] || continue
  warn duplicate "$id" "$count installs across different projects, so versions can drift apart"
done < "$SCRATCH/dupes"

# ==============
# CACHE
#   the disk layer: every version directory, whether or not a registry row still points at it
# ==============
# registered is decided by the registry's own installPath, never by reconstructing one: the layout
# is the harness's to change, and a rebuilt path would silently stop matching the rows it describes
cache_row() {
  local vpath=$1 plugin market state
  plugin=$(dirname "$vpath")
  market=$(dirname "$plugin")
  if grep -qF "	$vpath	" "$SCRATCH/installs" 2>/dev/null; then state=registered
  else state=orphan; fi
  printf '%s\t%s\t%s\t%s\t%s\n' "$(basename "$market")" "$(basename "$plugin")" \
    "$(basename "$vpath")" "$state" "$(size_of "$vpath")"
}

# every cached copy sits at <marketplace>/<plugin>/<version>, so one find pinned to that depth
# enumerates the whole layer without three nested loops guessing at the shape between them
: > "$SCRATCH/cache"
if [ -d "$CACHE" ]; then
  while IFS= read -r vpath; do
    [ -n "$vpath" ] || continue
    cache_row "$vpath" >> "$SCRATCH/cache"
  done < <(find "$CACHE" -mindepth 3 -maxdepth 3 -type d 2>/dev/null | sort)
fi

CACHE_COUNT=$(wc -l < "$SCRATCH/cache" | tr -d ' ')
ORPHANS=$(awk -F'\t' '$4 == "orphan"' "$SCRATCH/cache" | wc -l | tr -d ' ')
ORPHAN_KB=$(awk -F'\t' '$4 == "orphan" { t += $5 } END { print t + 0 }' "$SCRATCH/cache")
CACHE_KB=$(awk -F'\t' '{ t += $5 } END { print t + 0 }' "$SCRATCH/cache")

if [ "$ORPHANS" -gt 0 ]; then
  warn orphan cache "$ORPHANS version director(ies) no registry row points at, $(human "$ORPHAN_KB")"
fi

# ==============
# ENABLED
#   the consent layer: a name is claimed by whichever scope enables it, which is what shadows
# ==============
# one scope per call, so the caller reads as a list of paths rather than as a continued line, and
# a scope that carries no file is skipped rather than graded: absence is a valid settings state
scan_enabled() {
  local scope=$1
  [ -f "$scope" ] || return 0
  jq -r --arg s "$(mask "$scope")" \
    '(.enabledPlugins // {}) | to_entries[] | [ .key, $s, (.value | tostring) ] | @tsv' \
    "$scope" >> "$SCRATCH/enabled" 2>/dev/null && return 0
  err unreadable "$(mask "$scope")" "the scope exists but jq could not read its enabledPlugins"
}

: > "$SCRATCH/enabled"
scan_enabled "$HOME/.claude/settings.json"
scan_enabled "$ROOT/.claude/settings.json"
scan_enabled "$ROOT/.claude/settings.local.json"

ENABLED_COUNT=$(awk -F'\t' '$3 == "true"' "$SCRATCH/enabled" | wc -l | tr -d ' ')

# a name enabled with no install row behind it fails to load rather than falling through to a
# skills-dir copy of the same name, so it is an error even though nothing is broken on disk
while IFS=$'\t' read -r id scope value; do
  [ -n "${id:-}" ] || continue
  [ "$value" = "true" ] || continue
  grep -qF "$id	" "$SCRATCH/installs" 2>/dev/null && continue
  err enabled_missing "$id" "$scope enables it and no install row exists, so it cannot load"
done < "$SCRATCH/enabled"

# ==============
# SKILLS DIR
#   the directory layer: a plugin loaded from ~/.claude/skills, at user scope, in every project
# ==============
: > "$SCRATCH/skillsdir"
if [ -d "$SKILLSDIR" ]; then
  for entry in "$SKILLSDIR"/*/; do
    [ -e "$entry" ] || continue
    name=$(basename "$entry")
    epath=${entry%/}

    if [ -L "$epath" ]; then
      target=$(readlink "$epath")
      kind=symlink
    else
      target=$epath
      kind=directory
    fi

    if [ ! -d "$epath" ]; then
      err broken_link "$name" "points at $(mask "$target"), which does not resolve"
      printf '%s\t%s\t%s\t%s\t%s\n' "$name" "$kind" "$(mask "$target")" "-" "broken" \
        >> "$SCRATCH/skillsdir"
      continue
    fi

    # a manifest names the plugin, and the folder only suggests it; a copy renamed to dodge a
    # collision keeps its folder, so the manifest is what decides which name is actually claimed
    manifest="$epath/.claude-plugin/plugin.json"
    if [ -f "$manifest" ]; then
      declared=$(jq -r '.name // "?"' "$manifest" 2>/dev/null || echo '?')
      version=$(jq -r '.version // "?"' "$manifest" 2>/dev/null || echo '?')
    else
      declared=$name
      version="-"
      warn no_manifest "$name" "no .claude-plugin/plugin.json, so its version cannot be read"
    fi

    # the collision that matters is on the declared name against an ENABLED install; an installed
    # but disabled row frees the name, which is the cheapest way to hand a project the live copy
    state=loaded
    while IFS=$'\t' read -r id _scope value; do
      [ "$value" = "true" ] || continue
      [ "${id%%@*}" = "$declared" ] || continue
      state=shadowed
      warn shadowed "$declared" "$id is enabled, and an install outranks a skills-dir copy"
      break
    done < "$SCRATCH/enabled"

    printf '%s\t%s\t%s\t%s\t%s\n' "$declared" "$kind" "$(mask "$target")" "$version" "$state" \
      >> "$SCRATCH/skillsdir"
  done
fi

SKILLSDIR_COUNT=$(wc -l < "$SCRATCH/skillsdir" | tr -d ' ')
SHADOWED=$(awk -F'\t' '$5 == "shadowed"' "$SCRATCH/skillsdir" | wc -l | tr -d ' ')

# ==============
# DRIFT
#   a repo carrying the plugin sources can be compared against what is installed from them
# ==============
: > "$SCRATCH/drift"
if [ -d "$ROOT/plugins" ]; then
  for manifest in "$ROOT"/plugins/*/.claude-plugin/plugin.json; do
    [ -f "$manifest" ] || continue
    pname=$(jq -r '.name // "?"' "$manifest" 2>/dev/null || echo '?')
    pver=$(jq -r '.version // "?"' "$manifest" 2>/dev/null || echo '?')
    while IFS=$'\t' read -r id version _scope project _path _auto; do
      [ "${id%%@*}" = "$pname" ] || continue
      [ "$version" = "$pver" ] && continue
      printf '%s\t%s\t%s\t%s\n' "$pname" "$pver" "$version" "$(mask "$project")" >> "$SCRATCH/drift"
    done < "$SCRATCH/installs"
  done
fi

DRIFT_COUNT=$(wc -l < "$SCRATCH/drift" | tr -d ' ')
if [ "$DRIFT_COUNT" -gt 0 ]; then
  warn drift sources "$DRIFT_COUNT install(s) sit at a version this repo's manifests do not carry"
fi

# ==============
# PROJECT SKILLS
#   not plugins at all: a skill this repo carries directly, which no install or scope gates
# ==============
: > "$SCRATCH/project"
if [ -d "$ROOT/.claude/skills" ]; then
  for skill in "$ROOT"/.claude/skills/*/; do
    [ -d "$skill" ] || continue
    sname=$(basename "$skill")
    if [ -f "$skill/SKILL.md" ]; then tracked=$(git ls-files --error-unmatch \
      "${skill#"$ROOT"/}SKILL.md" >/dev/null 2>&1 && echo tracked || echo untracked)
    else tracked=no-doc; warn no_doc "$sname" "a project skill folder with no SKILL.md in it"; fi
    printf '%s\t%s\n' "$sname" "$tracked" >> "$SCRATCH/project"
  done
fi

PROJECT_COUNT=$(wc -l < "$SCRATCH/project" | tr -d ' ')

# ==============
# TELEMETRY
# ==============
ERRORS=$(grep -c '^ERROR|' "$FINDINGS" || true)
WARNINGS=$(grep -c '^WARN|' "$FINDINGS" || true)
ERRORS=${ERRORS:-0}; WARNINGS=${WARNINGS:-0}

# audit: one file per day per kind, so two triggers on the same day never interleave one file
# reported, never created: the sidecar names the path and the count, the agent writes the entry
TODAYS_AUDIT=".construct/operator/install/$(date +%Y-%m-%d).md"
if [ -f "$ROOT/$TODAYS_AUDIT" ];
then AUDIT_COUNT=$(grep -c '^## Install Audit #' "$ROOT/$TODAYS_AUDIT" || true)
else AUDIT_COUNT=0; fi
AUDIT_COUNT=${AUDIT_COUNT:-0}

if [ "$QUICK" -eq 1 ];
then MODE="quick — report inline, write nothing"; AUDIT_FILE=none
else MODE="audit — append to audit_file"; AUDIT_FILE=$TODAYS_AUDIT; fi

cat <<EOF

=== install.sh audit ===
mode: $MODE
audit_file: $AUDIT_FILE
audit_count: $AUDIT_COUNT
next_audit: $((AUDIT_COUNT + 1))
timestamp: $(date '+%Y-%m-%d %H:%M')
root: $(mask "$ROOT")
marketplaces: $MARKET_COUNT catalogue(s) trusted
installs: $INSTALL_COUNT registry row(s), $ENABLED_COUNT name(s) enabled
cache: $CACHE_COUNT version director(ies), $(human "$CACHE_KB") on disk, $ORPHANS orphan(ed)
skillsdir: $SKILLSDIR_COUNT plugin(s) under ~/.claude/skills, $SHADOWED shadowed
project: $PROJECT_COUNT skill(s) carried by this repo directly
errors: $ERRORS
warnings: $WARNINGS
--- marketplaces ---
EOF

if [ ! -s "$SCRATCH/markets" ]; then
  echo "none — no catalogue is trusted on this machine"
else
  printf '%-26s %-8s %-38s %-12s %s\n' name source repo ref auto
  awk -F'\t' '{ printf "%-26s %-8s %-38s %-12s %s\n", $1, $2, $3, $4, $6 }' "$SCRATCH/markets"
fi

echo "--- installs ---"
if [ ! -s "$SCRATCH/installs" ]; then
  echo "none — nothing is installed through a marketplace"
else
  printf '%-26s %-9s %-9s %-6s %s\n' plugin version scope auto project
  awk -F'\t' -v h="$HOME" \
    '{ p = $4; sub("^" h, "~", p); printf "%-26s %-9s %-9s %-6s %s\n", $1, $2, $3, $6, p }' \
    "$SCRATCH/installs"
fi

echo "--- cache on disk ---"
if [ ! -s "$SCRATCH/cache" ]; then
  echo "none — no plugin copy has been cached on this machine"
else
  printf '%-16s %-14s %-9s %-11s %s\n' marketplace plugin version state size
  awk -F'\t' '{ s = ($5 >= 1024) ? sprintf("%.1fM", $5 / 1024) : sprintf("%dK", $5);
    printf "%-16s %-14s %-9s %-11s %s\n", $1, $2, $3, $4, s }' "$SCRATCH/cache"
fi

echo "--- skills-dir plugins ---"
if [ ! -s "$SCRATCH/skillsdir" ]; then
  echo "none — ~/.claude/skills carries no plugin directory"
else
  printf '%-14s %-10s %-9s %-10s %s\n' name kind version state target
  awk -F'\t' '{ printf "%-14s %-10s %-9s %-10s %s\n", $1, $2, $4, $5, $3 }' "$SCRATCH/skillsdir"
fi

echo "--- enabled by scope ---"
if [ ! -s "$SCRATCH/enabled" ]; then
  echo "none — no settings scope enables a plugin"
else
  printf '%-26s %-8s %s\n' plugin enabled scope
  awk -F'\t' '{ printf "%-26s %-8s %s\n", $1, $3, $2 }' "$SCRATCH/enabled"
fi

echo "--- project skills ---"
if [ ! -s "$SCRATCH/project" ]; then
  echo "none — this repo carries no skill of its own"
else
  printf '%-22s %s\n' skill git
  awk -F'\t' '{ printf "%-22s %s\n", $1, $2 }' "$SCRATCH/project"
fi

if [ "$DRIFT_COUNT" -gt 0 ]; then
  echo "--- version drift against this repo's manifests ---"
  printf '%-16s %-11s %-11s %s\n' plugin manifest installed project
  awk -F'\t' '{ printf "%-16s %-11s %-11s %s\n", $1, $2, $3, $4 }' "$SCRATCH/drift"
fi

echo "--- findings ---"
if [ "$ERRORS" -eq 0 ] && [ "$WARNINGS" -eq 0 ]; then
  echo "none — every install resolves, every name loads the copy its scope selected"
else
  sort -t'|' -k1,1 -k2,2 "$FINDINGS" \
    | awk -F'|' '{ printf "%-5s %-16s %-24s %s\n", $1, $2, $3, $4 }'
fi

cat <<'EOF'
--- what this audit cannot tell you ---
- it reads the registry and the disk, so a session that has not restarted still runs the old set
- an enabled name is proven claimable, never proven loaded; only a live session resolves it
- a skills-dir copy is graded against enabled names, and the harness may break a tie another way
- the cache is sized with du, so a hard link shared between versions is counted under both
- version drift is only computed where a repo carries the plugin sources, so a consumer sees none
- nothing here reads a marketplace over the network, so a catalogue newer than its clone reads clean
- a project skill is listed, never validated; /validate-skills is what grades its shape
============================
EOF

if [ "$ERRORS" -gt 0 ]; then exit 1; fi
if [ "$STRICT" -eq 1 ] && [ "$WARNINGS" -gt 0 ]; then exit 1; fi
exit 0

#!/bin/bash
# ====================================================
# @file check-skills.sh - skill pair validator sidecar
# ====================================================
# @description
# PAIR
# - sidecar for `check-skills` — asserts every skill doc and its sidecar still hold together
# - the doc carries the shape a trigger follows; this file carries what a script can judge
# - the only spec whose sidecar scans `plugins/*/skills/`, not a `docs/` artifact directory
# SHAPE
# - a pair is one `SKILL.md` and one `<name>.sh`, sharing a folder named for the trigger
# - the doc keeps frontmatter as its orientation; the wayfinder lives in the sidecar, here
# - a trigger runs only when invoked; a spec loads whenever the model touches what it describes
# - the sidecar measures and never mutates, and sources `gitgud/shared/handover.sh` for its blocks
# - a sidecar needing to mutate emits the command into a block instead of running it
# RUN
# - defaults to every pair in `plugins/*/skills/`; pass a doc, a sidecar, or a directory to scope it
# - `--strict` promotes warnings to errors, `--keep` preserves scratch; exits 1 on any error
# - ERROR breaks a rule the doc states outright; WARN names a smell the doc tolerates
# @see AGENTS.md, tools/check-skills/README.md, plugins/gitgud/shared/handover.sh, plugins/, plugins/operator/shared/secrets.sh, .github/workflows/ci.yml

set -euo pipefail

# ==============
# PREFLIGHT
# ==============
# the shared scan sits beside this file, not beside the repo being scanned: resolve them before
# anything cds to a repo root, since BASH_SOURCE arrives relative and would follow that cd
SHARED=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../plugins/operator/shared" 2>/dev/null && pwd || true)
if [ ! -f "$SHARED/secrets.sh" ]; then
  echo "fatal: no plugins/operator/shared/secrets.sh reachable from this sidecar" >&2; exit 1; fi
# shellcheck source=../../plugins/operator/shared/secrets.sh
. "$SHARED/secrets.sh"

STRICT=0
KEEP=0
TEMPLATE="tools/check-skills/README.md"
TRIGGERS="plugins"

# the postures the index assigns; a trigger nobody can tell the blast radius of is a trap
POSTURES='READ-ONLY|SAFE|GATED|DESTRUCTIVE|RELEASE'

PAIRS=()
for arg in "$@"; do
  case "$arg" in
    --strict) STRICT=1;;
    --keep) KEEP=1;;
    -h|--help) sed -n '2,11p' "$0"; exit 0;;
    -*) echo "fatal: unknown flag $arg" >&2; exit 1;;
    *) PAIRS+=("$arg");;
  esac
done

# every check resolves paths from the repo root, since a trigger doc names its sidecar by full path
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "fatal: not a git repository" >&2; exit 1; fi
cd "$(git rev-parse --show-toplevel)"

if [ ${#PAIRS[@]} -eq 0 ]; then
  if [ ! -d "$TRIGGERS" ]; then echo "fatal: no $TRIGGERS/ to scan" >&2; exit 1; fi
  PAIRS=("$TRIGGERS")
fi

# a skill owns a directory, so the trigger's name is the folder rather than the file: every skill
# doc is called SKILL.md, and deriving the name from the file would call all of them 'skill'
trigger_name() {
  local doc=$1
  if [ "$(basename "$doc")" = 'SKILL.md' ]; then basename "$(dirname "$doc")"; return; fi
  basename "$doc" .md
}

# the doc half of a pair is a SKILL.md inside a lowercase skill folder; anything else in the tree
# is a reference doc rather than a trigger, and only the first kind is a pair
is_trigger_name() {
  [ "$(basename "$1")" = 'SKILL.md' ] || return 1
  printf '%s' "$(basename "$(dirname "$1")")" | grep -qE '^[a-z]+(-[a-z]+)*$'
}

# a sub-tool is invoked by another script rather than by a trigger, so it has no doc to pair with;
# listing them beats guessing, since nothing in the filename says which kind a script is
is_subtool() {
  case "$(basename "$1")" in
    permissions.sh|scopes.sh|secrets.sh|handover.sh) return 0;;
    *) return 1;;
  esac
}

# a pair is named by its doc, so a directory expands to the docs inside it and a sidecar maps back
# to the doc that is supposed to drive it — that mapping is what surfaces an orphaned script
EXPANDED=()
for path in "${PAIRS[@]}"; do
  if [ -d "$path" ]; then
    # a skill sits one level down in a plugin, and three down from the plugins/ root
    for nested in "$path"/*/SKILL.md "$path"/*/skills/*/SKILL.md "$path"/SKILL.md; do
      [ -f "$nested" ] || continue
      is_trigger_name "$nested" || continue
      EXPANDED+=("$nested")
    done
    for nested in "$path"/*/*.sh "$path"/*/skills/*/*.sh "$path"/*.sh; do
      [ -f "$nested" ] || continue
      is_subtool "$nested" && continue
      [ -f "$(dirname "$nested")/SKILL.md" ] || EXPANDED+=("$nested")
    done
  elif [ -f "$path" ]; then EXPANDED+=("$path")
  else echo "fatal: no such trigger file: $path" >&2; exit 1; fi
done
# set -u makes an empty array expansion fatal, which would read as a crash rather than a clean scan
if [ ${#EXPANDED[@]} -eq 0 ]; then echo "fatal: no skill pairs found under ${PAIRS[*]}" >&2; exit 1; fi
PAIRS=("${EXPANDED[@]}")

# the index that documents each trigger: a host project reaches it through the AGENTS.md symlink,
# and this repo is the one place where the same file is called README.md
INDEX=''
if [ -f AGENTS.md ]; then INDEX=AGENTS.md
elif [ -f README.md ]; then INDEX=README.md; fi

# repo-local scratch: the sandbox denies writes outside cwd, and macos mktemp ignores TMPDIR
TMPROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)/tmp"
TMPTAG=$(basename "${BASH_SOURCE[0]}" .sh)
mkdir -p "$TMPROOT"

# findings collect as "SEV|file|line|category|detail" — line is its own field so the report can
# sort numerically; joining it to the path first sorts 121 above 31. the run fails on ERROR only
FINDINGS=$(mktemp "$TMPROOT/$TMPTAG-findings.XXXXXX")
# a failed run leaves scratch behind to read; --keep does the same after a clean one
cleanup() { st=$?; if [ "$KEEP" -eq 0 ] && [ "$st" -eq 0 ]; then rm -f "$FINDINGS"; fi; }
trap cleanup EXIT

err()  { printf 'ERROR|%s|%s|%s|%s\n' "$1" "$2" "$3" "$4" >> "$FINDINGS"; }
warn() { printf 'WARN|%s|%s|%s|%s\n' "$1" "$2" "$3" "$4" >> "$FINDINGS"; }

# the line a pattern first lands on, so a finding points at the file's own line rather than line 1
where() {
  local hit
  hit=$(grep -nE "$2" "$1" 2>/dev/null | head -n 1 | cut -d: -f1 || true)
  printf '%s' "${hit:-1}"
}

# ==============
# CHECKS
#   each takes a doc path and appends findings; to add one, write a function and list it below
# ==============

# "one trigger doc per workflow, each paired with its shell sidecar" — the pair is what makes a
# trigger reachable, so the sidecar is looked for beside the doc rather than in one fixed folder
check_pair() {
  local doc=$1 name sidecar
  name=$(trigger_name "$doc")
  sidecar="$(dirname "$doc")/$name.sh"
  if ! printf '%s' "$name" | grep -qE '^[a-z]+(-[a-z]+)*$'; then
    err "$doc" 1 filename "the skill folder is the command name, so it is lowercase kebab-case"
  fi
  if [ ! -f "$sidecar" ]; then
    err "$doc" 1 unpaired "no $sidecar; every trigger doc starts with a shell sidecar"
    return 0
  fi
  if [ ! -x "$sidecar" ]; then
    warn "$sidecar" 1 not_executable "chmod +x, so the documented invocation works as written"
  fi
}

# the wayfinder now lives in the sidecar, which carries the whole pair; the doc keeps frontmatter
# as its orientation, so a reader gets the map from one file rather than two that can disagree
check_doc_wayfinding() {
  local doc=$1 name
  name=$(trigger_name "$doc")
  if grep -q '^```javascript' "$doc"; then
    err "$doc" 1 doc_wayfinder "the wayfinder belongs in $name.sh; the doc keeps frontmatter only"
  fi
  if [ "$(sed -n '1p' "$doc")" != '---' ]; then
    err "$doc" 1 frontmatter "line 1 opens the frontmatter, which is what orients a reader now"
  fi
  if ! grep -qE '^name:[[:space:]]*'"$name"'[[:space:]]*$' "$doc"; then
    err "$doc" 1 frontmatter "frontmatter needs 'name: $name', matching its folder"
  fi
  if ! grep -qE '^description:[[:space:]]*\S' "$doc"; then
    err "$doc" 1 frontmatter "frontmatter needs a description; it is the only listing a reader sees"
  fi
}

# "ran only on explicit `@gitautomation` commands" — the whole safety model rests on this line
check_trigger() {
  local doc=$1 name
  name=$(trigger_name "$doc")
  if ! grep -qE '^disable-model-invocation:[[:space:]]*(true|yes|on|1)[[:space:]]*$' "$doc"; then
    err "$doc" 1 trigger "frontmatter needs 'disable-model-invocation: true'; prose is not a gate"
  fi
}

# "starts with a native shell script sidecar" — the doc has to actually run the thing, in a block
# somebody can copy, and the path has to be the sidecar that belongs to it
check_invocation() {
  local doc=$1 name home
  name=$(trigger_name "$doc")
  home=$(dirname "$doc")
  if ! grep -qE "($home|skills/$name)/$name\.sh([[:space:]]|\"|$)" "$doc"; then
    err "$doc" 1 invocation "the doc never runs $home/$name.sh"
  fi
  # the bang block is what makes step one unskippable, since the harness runs it before any read
  if ! grep -qE '^```!' "$doc"; then
    warn "$doc" 1 invocation "run the sidecar from a \`\`\`! block, so it lands before the model reads"
  fi
}

# "fail: outputs raw terminal errors" and "success: evaluates telemetry and executes subsequent
# actions" — both branches, however each doc words them, since a sidecar that reports a conflict
# separately reads `> 1` where a two-state one reads `> 0`
check_branches() {
  local doc=$1
  # a report-only sidecar has exactly one path by contract, so it has no failure branch to document
  if grep -qE 'report-only|never fails' "$doc"; then return 0; fi
  if ! grep -qE '(exit code|sidecar exit)[^0-9]*(>|>=|!=)[[:space:]]*[0-9]|nonzero' "$doc"; then
    err "$doc" 1 no_failure_branch "no failure branch; say what happens when the sidecar exits nonzero"
  fi
  if ! grep -qE '(exit code|sidecar exit)[^0-9]*=+[[:space:]]*0' "$doc"; then
    err "$doc" 1 no_success_branch "no success branch; say what the telemetry means and what follows"
  fi
}

# a trigger that writes a dated artifact has to name the template that artifact must match, or the
# agent writing it has nothing to follow
check_artifact() {
  local doc=$1 type root
  # audits moved to their own root, one directory per kind; the write family still lives in docs/
  for type in graphs guides honest insights logs plans comments wayfinders permissions scopes settings credentials git; do
    case "$type" in
      graphs|guides|honest|insights|logs|plans) root="docs/$type/";;
      *) root="audits/$type/";;
    esac
    if ! grep -q "$root" "$doc"; then continue; fi
    # a cross-plugin reference is an invocation, since CLAUDE_PLUGIN_ROOT never leaves its plugin
    if ! grep -qE "plugins/[a-z]+/skills/(doc-)?${type%s}s?/SKILL\.md|/[a-z]+:(doc-)?${type%s}s?([^a-z-]|$)" "$doc"; then
      warn "$doc" "$(where "$doc" "$root")" artifact \
        "writes $root without naming the skill that owns that shape"
    fi
  done
}

# the sidecar is the half that touches git, so its own header and its shebang are load-bearing
check_sidecar_header() {
  local doc=$1 name sidecar
  name=$(trigger_name "$doc")
  sidecar="$(dirname "$doc")/$name.sh"
  if [ ! -f "$sidecar" ]; then return 0; fi
  if [ "$(sed -n '1p' "$sidecar")" != '#!/bin/bash' ]; then
    err "$sidecar" 1 shebang "line 1 must read '#!/bin/bash'"
  fi
  if ! grep -qE "^# @file $name\.sh - " "$sidecar"; then
    err "$sidecar" 1 wayfinding "@file must read '$name.sh - <short, specific title>'"
  fi
  if ! grep -q '^# @description' "$sidecar"; then
    err "$sidecar" 1 wayfinding "no @description; the header is what stops a reader guessing"
  fi
  if ! grep -q '^# @see' "$sidecar"; then
    err "$sidecar" 1 wayfinding "no @see; list every related internal file"
  fi
  # a read-only diagnostic may want to survive a failing probe, so this one only ever warns
  if ! grep -q 'set -euo pipefail' "$sidecar"; then
    warn "$sidecar" 1 no_strict_mode "no 'set -euo pipefail'; a silent partial run is worse than a stop"
  fi
}

# "the required check that lets `gh pr merge --auto` engage" runs the same two gates, so a sidecar
# that fails them locally has already failed ci
check_sidecar_lint() {
  local doc=$1 name sidecar hit line
  name=$(trigger_name "$doc")
  sidecar="$(dirname "$doc")/$name.sh"
  if [ ! -f "$sidecar" ]; then return 0; fi
  if ! bash -n "$sidecar" 2>/dev/null; then
    err "$sidecar" 1 syntax "does not parse; 'bash -n' is the first gate ci runs"
    return 0
  fi
  if ! command -v shellcheck >/dev/null 2>&1; then return 0; fi
  while IFS= read -r hit; do
    if [ -z "$hit" ]; then continue; fi
    line=$(printf '%s' "$hit" | cut -d: -f2)
    warn "$sidecar" "${line:-1}" shellcheck "$(printf '%s' "$hit" | cut -d: -f4- | sed 's/^ *//')"
  done < <(shellcheck -f gcc --severity=warning "$sidecar" 2>/dev/null || true)
}

# a trigger the index never lists is a trigger nobody discovers, and one listed without its posture
# is one nobody can judge the blast radius of before running it
check_index() {
  local doc=$1 name entry
  name=$(trigger_name "$doc")
  if [ -z "$INDEX" ]; then return 0; fi
  entry=$(grep -nE "\(plugins/[a-z]+/skills/$name/SKILL\.md\)" "$INDEX" | head -n 1 || true)
  if [ -z "$entry" ]; then
    err "$doc" 1 unindexed "$INDEX does not list /$name; nobody will find it"
    return 0
  fi
  if ! printf '%s' "$entry" | grep -qE "($POSTURES)"; then
    warn "$INDEX" "${entry%%:*}" no_posture "@$name is listed without a posture keyword"
  fi
}

# both halves of a pair get scanned, since a sidecar is as likely to hold a pasted token as its doc
check_scrub() {
  local doc=$1 name file
  name=$(trigger_name "$doc")
  for file in "$doc" "$(dirname "$doc")/$name.sh"; do
    if [ -f "$file" ]; then scan_secrets "$file"; fi
  done
}

# a trigger acts on the repo and is invoked deliberately; a spec describes a shape and should load
# whenever the model touches the thing it describes. the two earn opposite frontmatter, so the
# kind is declared rather than guessed; `metadata` exists for it and the harness ignores it
skill_kind() {
  local doc=$1 declared
  declared=$(awk '/^metadata:/ { inside = 1; next }
                  inside && /^[^[:space:]]/ { inside = 0 }
                  inside && /^[[:space:]]+kind:/ { gsub(/^[[:space:]]+kind:[[:space:]]*/, ""); print; exit }' "$doc")
  printf '%s' "${declared:-unset}"
}

# a spec must NOT carry the invocation gate, since the whole point is that the model reaches for it
check_spec() {
  local doc=$1
  if grep -qE '^disable-model-invocation:[[:space:]]*(true|yes|on|1)' "$doc"; then
    err "$doc" 1 spec_gated "a spec is meant to auto-load; drop disable-model-invocation"
  fi
}

# --- run list (add new checks here) ---
for pair in "${PAIRS[@]}"; do
  # a sidecar reaching this loop has no doc at all, so the pair checks have nothing to read
  case "$pair" in
    *.sh)
      err "$pair" 1 unpaired "no ${pair%.sh}.md; a sidecar without a trigger doc is unreachable"
      continue;;
  esac
  # every skill earns the shape checks; only a trigger earns the ones about being invoked
  check_pair            "$pair"
  check_doc_wayfinding  "$pair"
  check_sidecar_header  "$pair"
  check_sidecar_lint    "$pair"
  check_scrub           "$pair"
  case "$(skill_kind "$pair")" in
    spec)
      check_spec        "$pair";;
    trigger)
      check_trigger     "$pair"
      check_invocation  "$pair"
      check_branches    "$pair"
      check_artifact    "$pair"
      check_index       "$pair";;
    *)
      err "$pair" 1 no_kind "frontmatter needs 'metadata:' with 'kind: trigger' or 'kind: spec'";;
  esac
done

# ==============
# TELEMETRY
# ==============
ERRORS=$(grep -c '^ERROR|' "$FINDINGS" || true)
WARNINGS=$(grep -c '^WARN|' "$FINDINGS" || true)
SECRETS=$(grep -c '|secret|' "$FINDINGS" || true)

cat <<EOF

=== git.sh sidecar ===
template: $TEMPLATE
scanned: ${#PAIRS[@]} pair(s)
index: ${INDEX:-none found}
errors: $ERRORS
warnings: $WARNINGS
secrets: $SECRETS
--- findings ---
EOF

if [ "$ERRORS" -eq 0 ] && [ "$WARNINGS" -eq 0 ]; then
  echo "none — every machine-checkable rule holds"
else
  sort -t'|' -k1,1 -k2,2 -k3,3n "$FINDINGS" \
    | awk -F'|' '{ printf "%-5s %-50s %-17s %s\n", $1, $2 ":" $3, $4, $5 }'
fi

if [ "$SECRETS" -gt 0 ]; then
  cat <<EOF
--- secrets ---
STOP: $SECRETS unambiguous credential match(es) above
- do NOT truncate or edit anything yet; ask the user which match is real and what to do about it
- a key that already reached a commit is leaked, and truncating the file does not un-leak it
- rotate the credential first, then agree what the file should say in its place
EOF
fi
cat <<'EOF'
--- needs a human (template rules no script can judge) ---
- the trigger fires only on the explicit command, and is never inferred from intent
- failure hands back the raw terminal error, never a summary or a paraphrase of it
- success evaluates the telemetry first, and only then takes the documented action
- every scenario the sidecar can report has a branch in the doc that reads it
- destructive steps stay gated behind an explicit confirmation the user has to type
- the sidecar is the only half that touches git; the doc only decides what its output means
- the posture in the index matches what the sidecar actually does, not what it was written to do
- a key that reached a commit is already leaked; rotate it before rewriting anything
========================
EOF

if [ "$ERRORS" -gt 0 ]; then exit 1; fi
if [ "$STRICT" -eq 1 ] && [ "$WARNINGS" -gt 0 ]; then exit 1; fi
exit 0

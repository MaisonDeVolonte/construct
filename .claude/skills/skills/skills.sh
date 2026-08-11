#!/bin/bash
# ==============================================
# @file skills.sh - skill pair validator sidecar
# ==============================================
# @description
# PAIR
# - sidecar for `skills` — asserts every skill doc and its sidecar still hold together
# - the doc carries the shape a trigger follows; this file carries what a script can judge
# - the only spec whose sidecar scans `plugins/*/skills/`, not a `.construct/` artifact directory
# SHAPE
# - a pair is one `SKILL.md` and one `<name>.sh`, sharing a folder named for the trigger
# - the doc keeps frontmatter as its orientation; the wayfinder lives in the sidecar, here
# - a trigger runs only when invoked; a spec loads whenever the model touches what it describes
# - the sidecar measures and never mutates, and sources `gitgud/shared/handover.sh` for its blocks
# - a sidecar needing to mutate emits the command into a block instead of running it
# SPLIT
# - readme owns every frontmatter and preamble rule, judged at the readme source
# - this sidecar owns the rest of the pair: the body, the sidecar, the pairing, and the index
# - `metadata.kind` is still read here, since it decides which body checks a doc earns
# - a kind nobody declared is readme's ERROR; here it only warns that checks were skipped
# RUN
# - defaults to every pair in `plugins/*/skills/`; pass a doc, a sidecar, or a directory to scope it
# - `--strict` promotes warnings to errors, `--keep` preserves scratch; exits 1 on any error
# - ERROR breaks a rule the doc states outright; WARN names a smell the doc tolerates
# @see .claude/skills/skills/SKILL.md, .claude/skills/readme/readme.sh, plugins/gitgud/shared/handover.sh, plugins/, plugins/operator/shared/secrets.sh, .github/workflows/ci.yml

set -euo pipefail

# ==============
# PREFLIGHT
# ==============
# the shared scan sits beside this file, not beside the repo being scanned: resolve them before
# anything cds to a repo root, since BASH_SOURCE arrives relative and would follow that cd
SHARED=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../plugins/operator/shared" 2>/dev/null && pwd || true)
if [ ! -f "$SHARED/secrets.sh" ]; then
  echo "fatal: no plugins/operator/shared/secrets.sh reachable from this sidecar" >&2; exit 1; fi
# shellcheck source=../../../plugins/operator/shared/secrets.sh
. "$SHARED/secrets.sh"

STRICT=0
KEEP=0
TEMPLATE=".claude/skills/skills/SKILL.md"
TRIGGERS="plugins"

# the postures the index assigns; a trigger nobody can tell the blast radius of is a trap
POSTURES='READ-ONLY|SAFE|GATED|DESTRUCTIVE|RELEASE'

# the exact line every doc runs to inject its plugin's output style, frontmatter shed
VOICE_CMD='awk '"'"'NR>1 && /^---$/ {p=1; next} p'"'"' "${CLAUDE_PLUGIN_ROOT}/output-styles/operator.md"'

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

# plugins/<plugin>/skills/<name>/ — the plugin is the namespace half of every invocation, and the
# first half of the artifact path, so two checks read it off the doc's own location
plugin_of() {
  printf '%s' "$1" | sed -n 's|.*plugins/\([a-z][a-z-]*\)/skills/.*|\1|p'
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
    permissions.sh|scripts.sh|secrets.sh|handover.sh|triage.sh) return 0;;
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

# the index that documents each trigger: README is the only one now, since the AGENTS.md symlink
# that used to shadow it is retired and a plugin ships its instructions through skills instead
INDEX=''
if [ -f README.md ]; then INDEX=README.md; fi

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
# as its orientation, and readme judges that frontmatter at its readme source
check_doc_wayfinding() {
  local doc=$1 name
  name=$(trigger_name "$doc")
  if grep -q '^```javascript' "$doc"; then
    err "$doc" 1 doc_wayfinder "the wayfinder belongs in $name.sh; the doc keeps frontmatter only"
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
# `.construct/<plugin>/<skill>/` names its own owner, so ownership is read off the path itself and
# the kind list and its singular/plural lookup are both gone; a doc naming a path that is not its
# own is reaching across a boundary, and that reference has to be an invocation rather than a path
check_artifact() {
  local doc=$1 name plugin own ref refplugin refskill
  name=$(trigger_name "$doc")
  plugin=$(plugin_of "$doc")
  [ -n "$plugin" ] || return 0
  own=".construct/$plugin/$name/"
  while IFS= read -r ref; do
    [ -n "$ref" ] || continue
    [ "$ref" = "$own" ] && continue
    refplugin=$(printf '%s' "$ref" | cut -d/ -f2)
    refskill=$(printf '%s' "$ref" | cut -d/ -f3)
    if ! grep -qE "/$refplugin:$refskill([^a-z-]|$)" "$doc"; then
      warn "$doc" "$(where "$doc" "$ref")" artifact \
        "names $ref without the /$refplugin:$refskill invocation that owns it"
    fi
  done < <(grep -oE '\.construct/[a-z-]+/[a-z-]+/' "$doc" | sort -u || true)
}

# a block header carries the name a user typed, so it survives a rename only if something checks it
# four sidecars printed a name one or two renames stale, and two docs already quoted the right one
check_block_name() {
  local doc=$1 name plugin sidecar want n found
  name=$(trigger_name "$doc")
  sidecar="$(dirname "$doc")/$name.sh"
  [ -f "$sidecar" ] || return 0
  plugin=$(plugin_of "$doc")
  [ -n "$plugin" ] || return 0
  want="$plugin:$name"
  while IFS=$'\t' read -r n found; do
    [ -n "$n" ] || continue
    found=$(printf '%s' "$found" | sed -E 's/.*_open[[:space:]]+"?([^"[:space:]]+)"?.*/\1/')
    [ "$found" = "$want" ] && continue
    err "$sidecar" "$n" block_name "block opens '$found' where the invocation is '$want'"
  done < <(grep -nE '(telemetry|handover|trigger)_open[[:space:]]+"?[A-Za-z]' "$sidecar" 2>/dev/null | sed 's/:/\t/' || true)
}

# the body checks: a doc can be shape-correct in its frontmatter and its pairing and still be
# structurally broken inside, which is how a pasted shape corrupted two docs with 0 errors reported
check_body() {
  local doc=$1 n num prev heading ticks own plugin want found template

  # the first `# ` heading is where a doc stops instructing and starts templating, so it is the
  # boundary every check below needs: numbered lines above it are steps, below it they are example
  # content. a doc with no template region has no boundary and is scanned whole
  # `|| true` on every one of these: grep exits 1 when it matches nothing, which under `set -e`
  # and `pipefail` kills the run mid-walk and reports zero findings, reading exactly like a pass
  template=$(grep -nE '^# ' "$doc" 2>/dev/null | head -1 | cut -d: -f1 || true)
  template=${template:-999999}

  # steps read in file order and must climb: a repeated number is two step 3s, and a number that
  # drops is a block pasted in below the step it duplicates. one rule catches both
  prev=0
  while IFS=$'\t' read -r n heading; do
    [ -n "$n" ] || continue
    [ "$n" -lt "$template" ] || continue
    num=$(printf '%s' "$heading" | sed -n 's/^\([0-9]\{1,\}\)\..*/\1/p')
    [ -n "$num" ] || continue
    if [ "$num" -le "$prev" ]; then
      err "$doc" "$n" step_order "step $num follows step $prev; a step number appears once, ascending"
    fi
    prev=$num
  done < <(grep -nE '^[0-9]+\. ' "$doc" | sed 's/:/\t/' || true)

  # a heading closing no backtick it opened is the fingerprint of a bulk edit that ate a line: it
  # renders as a heading, so nothing downstream complains, and the text it swallowed is just gone
  while IFS=$'\t' read -r n heading; do
    [ -n "$n" ] || continue
    ticks=$(printf '%s' "$heading" | tr -cd '`' | wc -c | tr -d ' ')
    if [ $((ticks % 2)) -ne 0 ]; then
      err "$doc" "$n" heading_backtick "heading opens a backtick it never closes"
    fi
  done < <(grep -nE '^#{1,6} ' "$doc" | sed 's/:/\t/' || true)

  # an unfilled placeholder is the pasted generic shape itself, still carrying `<kind>` and
  # `<Kind>` where the skill's own name belongs. it reads as a template rather than a spec, and it
  # is what a path check can never catch, since a placeholder names no path to disagree with
  n=$(grep -nE '^# \.construct/<|^## <[A-Za-z]+> Audit #' "$doc" 2>/dev/null | head -1 | cut -d: -f1 || true)
  if [ -n "$n" ]; then
    err "$doc" "$n" shape_placeholder \
      "the archive shape still carries its <kind> placeholders; write it for this skill"
    return 0
  fi

  # an archive shape naming another skill's artifact is what a pasted block leaves behind, and the
  # agent silently corrects for it, so the artifacts on disk never show the doc is wrong
  # the path is read off the template's own h1 and compared to the doc's own location, which is
  # exact: a pasted shape carries the source skill's full path and disagrees on the first segment
  own=$(sed -n 's|^# \(\.construct/[a-z-]*/[a-z-]*/\).*|\1|p' "$doc" | head -1)
  [ -n "$own" ] || return 0
  plugin=$(plugin_of "$doc")
  [ -n "$plugin" ] || return 0
  want=".construct/$plugin/$(trigger_name "$doc")/"
  if [ "$own" != "$want" ]; then
    n=$(where "$doc" '^# \.construct/')
    err "$doc" "$n" shape_path "the archive shape writes $own where this skill owns $want"
  fi

  # every audit heading in one doc names the same subject; two vocabularies is half a paste
  prev=''
  while IFS=$'\t' read -r n heading; do
    [ -n "$n" ] || continue
    found=$(printf '%s' "$heading" | sed -n 's/^## \([A-Za-z]\{1,\}\) Audit #.*/\1/p')
    [ -n "$found" ] || continue
    if [ -n "$prev" ] && [ "$found" != "$prev" ]; then
      err "$doc" "$n" shape_heading "a '$found' audit heading where the shape already said '$prev'"
    fi
    prev=$found
  done < <(grep -nE '^## [A-Za-z]+ Audit #' "$doc" | sed 's/:/\t/' || true)
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

# the style is opt-in, so the voice block is the only thing carrying it into a turn that did not
# choose it; a paraphrased command cats nothing, so this compares byte for byte rather than by shape
check_voice() {
  local doc=$1 plugin
  if ! grep -qFx -- "$VOICE_CMD" "$doc"; then
    err "$doc" 1 no_voice "no voice block; the plugin style only reaches a turn when the doc cats it"
    return 0
  fi
  if ! grep -qE '^## voice$' "$doc"; then
    err "$doc" "$(where "$doc" 'output-styles/operator\.md')" voice_heading \
      "the voice command runs under no '## voice' heading, so nothing names what the block is"
  fi
  plugin=$(plugin_of "$doc")
  [ -n "$plugin" ] || return 0
  if [ ! -f "plugins/$plugin/output-styles/operator.md" ]; then
    err "$doc" 1 voice_missing_style \
      "the block cats plugins/$plugin/output-styles/operator.md and the file is not there"
  fi
}

# a trigger the index never lists is a trigger nobody discovers, and one listed without its posture
# is one nobody can judge the blast radius of before running it
check_index() {
  local doc=$1 name plugin entry
  name=$(trigger_name "$doc")
  plugin=$(plugin_of "$doc")
  if [ -z "$INDEX" ] || [ -z "$plugin" ]; then return 0; fi
  # the readme names a skill two ways: a bare invocation fenced under its catalog entry, and a
  # linked SKILL.md path in the audits list. either is discoverable, and only the second carries
  # a posture, so the fenced form returns clean rather than warning on a column it never had
  if grep -qE "^/$plugin:${name}[[:space:]]*$" "$INDEX"; then return 0; fi
  entry=$(grep -nE "\(plugins/[a-z]+/skills/$name/SKILL\.md\)" "$INDEX" | head -n 1 || true)
  if [ -z "$entry" ]; then
    err "$doc" 1 unindexed "$INDEX does not list /$plugin:$name; nobody will find it"
    return 0
  fi
  if ! printf '%s' "$entry" | grep -qE "($POSTURES)"; then
    warn "$INDEX" "${entry%%:*}" no_posture "/$plugin:$name is listed without a posture keyword"
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
# whenever the model touches the thing it describes. the kind gates which body checks run here;
# whether it is declared correctly is readme's rule, judged at the readme source
skill_kind() {
  local doc=$1 declared
  declared=$(awk '/^metadata:/ { inside = 1; next }
                  inside && /^[^[:space:]]/ { inside = 0 }
                  inside && /^[[:space:]]+kind:/ { gsub(/^[[:space:]]+kind:[[:space:]]*/, ""); print; exit }' "$doc")
  printf '%s' "${declared:-unset}"
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
  check_body            "$pair"
  check_block_name      "$pair"
  check_voice           "$pair"
  case "$(skill_kind "$pair")" in
    spec) ;;
    trigger)
      check_invocation  "$pair"
      check_branches    "$pair"
      check_artifact    "$pair"
      check_index       "$pair";;
    *)
      warn "$pair" 1 no_kind "kind unset, so the trigger checks were skipped; readme owns the rule";;
  esac
done

# ==============
# TELEMETRY
# ==============
ERRORS=$(grep -c '^ERROR|' "$FINDINGS" || true)
WARNINGS=$(grep -c '^WARN|' "$FINDINGS" || true)
SECRETS=$(grep -c '|secret|' "$FINDINGS" || true)

cat <<EOF

=== /skills telemetry ===
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

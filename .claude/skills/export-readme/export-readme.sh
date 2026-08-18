#!/bin/bash
# ===========================================================
# @file export-readme.sh - readme to managed-region exporter
# ===========================================================
# @description
# SOURCE
# - the readme's catalog is the source of truth for every skill's frontmatter and preamble
# - each mapped `#### <Skill>` section carries a yaml fence, then the preamble that follows it
# - `map.json` beside this file names which readme heading feeds which target file
# - a map value may be a list, so one section exports into every copy that has to agree
# - the `README.md` entry names no section at all: the source file itself is what lands
# REGION
# - a skill's managed region runs from line 1 to the first body heading after its frontmatter
# - a style file has no such heading, so its whole file is the region and the export owns it
# - a script target (*.sh) is the same whole-file region, rendered from its section's bash fence
# - a readme copy (plugins/*/README.md) is the source verbatim, so its compare is a byte compare
# - export replaces that region with the section's yaml inner block plus its trailing markdown
# - the bare invocation fence above the yaml block is readme display sugar and never lands
# CHECKS
# - every frontmatter rule lives here now, judged at the readme source before anything lands
# - required fields: name, license, compatibility, description; triggers add model and effort
# - `metadata.kind` is declared; a trigger sets disable-model-invocation: true, a spec must not
# - `description` stays at or under 110 chars; description + when_to_use stays under the 1536 cap
# - `name` must match the skill's folder, and every SKILL.md on disk must appear in the map
# - a hook doc under plugins/*/hooks/ is style-shaped: name and description, no kind, no cap
# - every hook action script must carry a mapped doc beside it, so an undocumented action errors
# - a style target earns name and description only; a script earns a fence opening #!/bin/bash
# - a readme copy carries no yaml, so drift is its only finding and an absent copy is drift too
# - any ERROR on a section blocks that one skill's export and never the others
# RUN
# - a bare run exports: every unblocked drifted region is rewritten from its readme section
# - `--check` writes nothing and exits 1 on any drift, which is the one mode ci runs
# - the NEWER column reads file mtimes, and a copy that moved after the readme refuses to export
# - a refused row prints its own diff, since the edit it protects is the one about to be lost
# - pass skill names to scope either mode; the map and the source are fixed, and edited by hand
# ARTIFACT
# - `.construct/maintainer/export-readme/YYYY-MM-DD.md`, one file per day, appended by the agent
# - reported, never created: this names the path and the count, and the doc says what to write
# - a `--check` that passed is worth keeping, since it dates the last moment the tree agreed
# @see .claude/skills/export-readme/map.json, .claude/skills/export-readme/SKILL.md, .claude/skills/validate-skills/validate-skills.sh, README.md, .github/workflows/ci.yml, .construct/maintainer/export-readme/
set -euo pipefail

# the doc is read only after this has already run, so help is refused here or not at all; the doc's
# own '## Help' section owns the output, which is why this prints a marker rather than a usage text
case " $* " in *" --help "*|*" -h "*) echo "help: requested"; exit 0;; esac

# the smoke case proves this file parses and its guards return; /test-skills reads the sources,
# the @see paths and the tool guards statically, so nothing here runs a step of the skill
case " $* " in *" --test "*) echo "test: ok"; exit 0;; esac

# the day's artifact is named here and written by the agent, the same split every other skill in
# this repo makes; a sidecar that wrote it too would be a second author of `.construct`
ARTIFACTS=".construct/maintainer/export-readme"

CHECK=0
MAP=".claude/skills/export-readme/map.json"
SOURCE="README.md"
REQUIRED="name license compatibility description"
# a style carries no license, no compatibility and no kind; it is a prompt, not an invocation
REQUIRED_STYLE="name description"
# model and effort route an invocation, so only a trigger needs them; on a spec they are dead config
REQUIRED_TRIGGER="model effort"
# a cap, not a band: a short description that already says the whole thing needs no padding
DESC_MAX=110
# the harness truncates `description` + `when_to_use` at this many characters in the skill listing
LISTING_CAP=1536
# 80% of the cap: near enough that the next edit is the one that drops text without saying so
LISTING_WARN=1228

ONLY=()
while [ $# -gt 0 ]; do
  case "$1" in
    --check) CHECK=1;;
    -*) echo "fatal: unknown flag $1" >&2; exit 1;;
    *) ONLY+=("$1");;
  esac
  shift
done

# every path in the map is repo-root relative, so the run anchors there like its siblings do
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "fatal: not a git repository" >&2; exit 1; fi
cd "$(git rev-parse --show-toplevel)"

command -v jq >/dev/null 2>&1 || { echo "fatal: jq is required to read $MAP" >&2; exit 1; }
[ -f "$MAP" ] || { echo "fatal: no map at $MAP" >&2; exit 1; }
[ -f "$SOURCE" ] || { echo "fatal: no source at $SOURCE" >&2; exit 1; }
jq -e 'type == "object"' "$MAP" >/dev/null 2>&1 \
  || { echo "fatal: $MAP is not a json object of heading -> skill path" >&2; exit 1; }

# repo-local scratch: the sandbox denies writes outside cwd, and macos mktemp ignores TMPDIR
TMPROOT="$(git rev-parse --show-toplevel)/tmp"
mkdir -p "$TMPROOT"
SCRATCH=$(mktemp -d "$TMPROOT/readme.XXXXXX")
cleanup() { st=$?; rm -rf "$SCRATCH"; exit "$st"; }
trap cleanup EXIT

# findings collect as "SEV|file|line|category|detail"; drift rows as "label|path|region|delta"
FINDINGS="$SCRATCH/findings"
ROWS="$SCRATCH/rows"
QUEUE="$SCRATCH/queue"
# the rows a copy-side edit refused, so the run can show each one the diff it is protecting
REFUSED="$SCRATCH/refused"
# the left side of a compare when the target is not there yet; a real file rather than /dev/null,
# since the sandbox denies that too and a failed diff reports a delta of zero
EMPTY="$SCRATCH/absent"
: > "$FINDINGS"; : > "$ROWS"; : > "$QUEUE"; : > "$EMPTY"; : > "$REFUSED"

err()  { printf 'ERROR|%s|%s|%s|%s\n' "$1" "$2" "$3" "$4" >> "$FINDINGS"; }
warn() { printf 'WARN|%s|%s|%s|%s\n' "$1" "$2" "$3" "$4" >> "$FINDINGS"; }

# a copy whose mtime is newer than the readme's holds an edit nobody moved into the source yet, so
# the export refuses that one section; the alternative is a silent overwrite of the fresher side
refuse() {
  err "$2" 1 copy_newer "this copy moved after $SOURCE, so exporting would discard that edit"
  printf '%s|%s|%s\n' "$1" "$2" "$3" >> "$REFUSED"
  BLOCKED=$((BLOCKED + 1))
}

# the exact heading line in the source, so a finding points at the readme rather than line 1
heading_line() {
  grep -nFx "$1" "$SOURCE" 2>/dev/null | head -n 1 | cut -d: -f1 || true
}

# a section runs from its heading to the next heading of the same or a higher level; a heading
# inside a fenced example is content, so fences toggle the check off
section_body() {
  local heading=$1 hashes level
  hashes=${heading%% *}
  level=${#hashes}
  awk -v h="$heading" -v level="$level" '
    !insec { if ($0 == h) insec = 1; next }
    /^```/ { fence = !fence }
    !fence && /^#/ {
      n = 0
      while (substr($0, n + 1, 1) == "#") n++
      if (n <= level && substr($0, n + 1, 1) == " ") exit
    }
    { print }
  ' "$SOURCE"
}

# what the skill top becomes: the yaml fence's inner lines, then everything after its close
# whatever sits above the yaml fence is readme display sugar and is dropped
render_top() {
  awk '
    state == 0 && /^```yaml[[:space:]]*$/ { state = 1; next }
    state == 1 && /^```[[:space:]]*$/ { state = 2; next }
    state == 1 { print; next }
    state == 2 { print }
  ' "$1"
}

# what a script file becomes: the first ```bash fence's inner lines and nothing else; the prose
# around the fence is readme documentation and never lands in a copy
render_script() {
  awk '
    state == 0 && /^```bash[[:space:]]*$/ { state = 1; next }
    state == 1 && /^```[[:space:]]*$/ { state = 2; next }
    state == 1 { print }
  ' "$1"
}

# the managed region ends at the first `# ` or `## ` after the frontmatter closes; a heading
# inside a fenced preamble example is content, so fences toggle here too
region_end() {
  awk '
    NR == 1 && $0 == "---" { fm = 1; next }
    fm == 1 { if ($0 == "---") fm = 2; next }
    fm == 2 && /^```/ { fence = !fence; next }
    fm == 2 && !fence && /^##? / { found = 1; print NR; exit }
    END { if (!found) print NR + 1 }
  ' "$1"
}

# trailing blank lines carry no meaning, so both sides shed them before any compare or write
strip_trailing() {
  awk '{ buf[NR] = $0; if ($0 !~ /^[[:space:]]*$/) last = NR }
       END { for (i = 1; i <= last; i++) print buf[i] }' "$@"
}

# one frontmatter value, quotes shed, folded scalars unwrapped; mirrors validate-skills.sh
field_of() {
  local yaml=$1 key=$2 value
  value=$(awk -v key="$key" '
    NR == 1 && $0 == "---" { open = 1; next }
    !open { exit }
    $0 == "---" { exit }
    folded && /^[[:space:]]/ { sub(/^[[:space:]]+/, ""); buffer = buffer " " $0; next }
    folded { exit }
    $0 ~ "^" key ":" {
      buffer = $0
      sub("^" key ":[[:space:]]*", "", buffer)
      if (buffer ~ /^[>|][-+]?$/) { folded = 1; buffer = ""; next }
      exit
    }
    END { print buffer }
  ' "$yaml")
  value=${value#\"}; value=${value%\"}
  value=${value#\'}; value=${value%\'}
  printf '%s' "$value"
}

# plugins/<plugin>/ names the invocation half; a fixture path outside plugins/ has none
plugin_of() {
  printf '%s' "$1" | sed -n 's|.*plugins/\([a-z][a-z-]*\)/.*|\1|p'
}

# a style earns name and description only; the harness scans output-styles/ and never its sibling
is_style() {
  case "$1" in */output-styles/*.md|*/subagent-styles/*.md) return 0;; *) return 1;; esac
}

# a skill pastes the brief into every invocation, so an uncapped one stops being light unseen
is_brief() {
  case "$1" in */subagent-styles/*.md) return 0;; *) return 1;; esac
}
BRIEF_CAP=2500

# a hook action's doc is style-shaped for the same reason: nothing invokes it by name, so it earns
# name and description only, and the drift compare is the reason it is mapped at all
is_hookdoc() {
  case "$1" in */hooks/*/*.md) return 0;; *) return 1;; esac
}

# a script target is a shell file exported whole from its section's bash fence; it has no yaml
# at all, so it earns even fewer checks than a style and exactly the same drift compare
is_script() {
  case "$1" in *.sh) return 0;; *) return 1;; esac
}

# a readme copy is the source landed whole at a plugin root, so an install taking one plugin's
# directory still carries the doc; with no section and no yaml, cmp is its every rule
is_readme() {
  case "$1" in */README.md) return 0;; *) return 1;; esac
}

# which side moved last, so a drift row says which copy to read before anything is written. file
# mtimes rather than commit times, since the edit that caused the drift is usually still uncommitted
# the source mtime is file-level, so editing one section marks it newer than every copy; the column
# answers "did the readme move after this copy did", which is the question to ask before applying
newer_side() {
  local target=$1
  if [ ! -f "$target" ]; then printf 'readme'; return 0; fi
  if [ "$SOURCE" -nt "$target" ]; then printf 'readme'; return 0; fi
  if [ "$target" -nt "$SOURCE" ]; then printf 'copy'; return 0; fi
  printf 'same'
}

# who may invoke this skill, read from the one field the harness itself acts on: a doc setting
# disable-model-invocation is user-invoked, and anything else is model-invocable (see #6)
user_invoked() {
  grep -qE '^disable-model-invocation:[[:space:]]*(true|yes|on|1)[[:space:]]*$' "$1"
}

# a scope argument matches the skill folder or the plugin:name label, nothing fuzzier
in_scope() {
  local name=$1 label=$2 want
  [ ${#ONLY[@]} -eq 0 ] && return 0
  for want in "${ONLY[@]}"; do
    if [ "$want" = "$name" ] || [ "$want" = "$label" ]; then return 0; fi
  done
  return 1
}

# ==============
# ANALYZE
#   pass one reads every mapped pair, collects findings and drift; nothing is written yet
# ==============
MAPPED=0
IN_SYNC=0
DRIFTED=0
BLOCKED=0
PEAK=0
PEAK_LABEL='none'
pair=0

while IFS=$'\t' read -r heading skill; do
  [ -n "$heading" ] || continue
  # a skill owns a folder and every doc is called SKILL.md; a style or a script is one file each,
  # and a readme copy takes the scope word rather than its shouted basename, like every sibling
  if is_readme "$skill"; then name=readme
  elif is_style "$skill" || is_hookdoc "$skill"; then name=$(basename "$skill" .md)
  elif is_script "$skill"; then name=$(basename "$skill" .sh)
  else name=$(basename "$(dirname "$skill")"); fi
  plugin=$(plugin_of "$skill")
  label=${plugin:+$plugin:}$name
  in_scope "$name" "$label" || continue
  MAPPED=$((MAPPED + 1))
  pair=$((pair + 1))
  blocked=0

  # a readme copy names no section, so every heading, yaml and fence rule below would judge text
  # it does not have; the source file is the whole region and cmp is the whole compare
  if is_readme "$skill"; then
    if [ ! -d "$(dirname "$skill")" ]; then
      err "$skill" 1 missing_plugin "the map lands a copy in a directory that is not there"
      BLOCKED=$((BLOCKED + 1))
      continue
    fi
    # an absent copy is drift and not a scaffold error: unlike a skill there is no body to invent,
    # so a plugin added to the map earns its copy on the next apply
    have=$skill
    if [ ! -f "$have" ]; then have=$EMPTY; fi
    if cmp -s "$have" "$SOURCE"; then
      IN_SYNC=$((IN_SYNC + 1))
      continue
    fi
    DRIFTED=$((DRIFTED + 1))
    region='file (verbatim)'
    if [ "$have" = "$EMPTY" ]; then region='file (absent)'; fi
    delta=$(diff "$have" "$SOURCE" | grep -c '^[<>]' || true)
    newer=$(newer_side "$skill")
    printf '%s|%s|%s|%s|%s|%s\n' "$label" "$skill" "$region" "$delta" "$newer" "$pair" >> "$ROWS"
    if [ "$newer" = copy ]; then
      refuse "$label" "$skill" "$pair"
      continue
    fi
    # boundary 0 marks the whole-file copy the export lands with cp, since a render that rewrote
    # a single byte would break the one contract this target has
    printf '%s|%s|%s|%s\n' "$label" "$skill" 0 "$SOURCE" >> "$QUEUE"
    continue
  fi

  hline=$(heading_line "$heading")
  if [ -z "$hline" ]; then
    err "$SOURCE" 1 missing_section "the map names '$heading' and the readme has no such line"
    BLOCKED=$((BLOCKED + 1))
    continue
  fi
  # two identical headings would export whichever came first, silently; refuse to guess
  if [ "$(grep -cFx "$heading" "$SOURCE" || true)" -gt 1 ]; then
    err "$SOURCE" "$hline" duplicate_heading "'$heading' appears more than once; the map needs one"
    BLOCKED=$((BLOCKED + 1))
    continue
  fi

  section="$SCRATCH/$pair.section"
  newtop="$SCRATCH/$pair.newtop"
  section_body "$heading" > "$section"
  if is_script "$skill"; then render_script "$section" | strip_trailing > "$newtop"
  else render_top "$section" | strip_trailing > "$newtop"; fi

  # a script's whole contract at the source is its fence; every yaml rule below belongs to the
  # kinds that carry frontmatter, so a script skips from here to the drift compare
  if is_script "$skill"; then
    if [ ! -s "$newtop" ] || [ "$(sed -n '1p' "$newtop")" != '#!/bin/bash' ]; then
      err "$SOURCE" "$hline" no_fence "'$heading' carries no \`\`\`bash fence opening with #!/bin/bash"
      BLOCKED=$((BLOCKED + 1))
      continue
    fi
  else

  if [ ! -s "$newtop" ] || [ "$(sed -n '1p' "$newtop")" != '---' ]; then
    err "$SOURCE" "$hline" no_yaml "'$heading' carries no \`\`\`yaml fence opening with ---"
    BLOCKED=$((BLOCKED + 1))
    continue
  fi
  if ! awk 'NR > 1 && $0 == "---" { found = 1; exit } END { exit !found }' "$newtop"; then
    err "$SOURCE" "$hline" no_yaml "'$heading' has a yaml block whose --- never closes"
    blocked=1
  fi

  # the checks run against the readme yaml, since that is the text an export would land
  got=$(field_of "$newtop" name)
  if [ -n "$got" ] && [ "$got" != "$name" ]; then
    err "$SOURCE" "$hline" name_mismatch "'$heading' says 'name: $got' and maps to $skill"
    blocked=1
  fi
  required=$REQUIRED
  if is_style "$skill" || is_hookdoc "$skill"; then required=$REQUIRED_STYLE; fi
  for key in $required; do
    if ! grep -qE "^$key:[[:space:]]*\S" "$newtop"; then
      err "$SOURCE" "$hline" missing_field "'$heading' yaml has no '$key:'; the field is required"
      blocked=1
    fi
  done

  # the brief is pasted into every skill invocation, so its size is the contract, not a nit
  if is_brief "$skill"; then
    bytes=$(wc -c < "$newtop" | tr -d ' ')
    if [ "$bytes" -gt "$BRIEF_CAP" ]; then
      err "$SOURCE" "$hline" brief_too_large \
        "'$heading' renders $bytes bytes against a $BRIEF_CAP cap; cut a section, do not wrap it"
      blocked=1
    fi
  fi

  # a style or a hook doc is not listed, not invoked and has no kind, so the rules below judge
  # fields it would never carry; everything after them is the drift compare it is mapped for
  if is_style "$skill" || is_hookdoc "$skill"; then
    desc=''
    wtu=''
  else

  desc=$(field_of "$newtop" description)
  if [ -n "$desc" ]; then
    if [ ${#desc} -gt "$DESC_MAX" ]; then
      warn "$SOURCE" "$hline" description_length \
        "'$heading' description is ${#desc} chars; the cap is $DESC_MAX"
    fi
  fi

  # every skill answers --help, and the hint is the only place the picker shows a flag before it is
  # typed; leading with it keeps one skill from advertising the flag while its sibling hides it
  if ! grep -qE '^argument-hint: "\[--help\]' "$newtop"; then
    err "$SOURCE" "$hline" help_unhinted \
      "'$heading' has no argument-hint leading with [--help]; every skill answers it"
    blocked=1
  fi

  # a user-invoked skill routes an invocation, so it needs the fields that route one; a
  # model-invocable one is loaded by relevance and both fields are dead config on it
  if user_invoked "$newtop"; then
    for key in $REQUIRED_TRIGGER; do
      if ! grep -qE "^$key:[[:space:]]*\S" "$newtop"; then
        err "$SOURCE" "$hline" missing_field \
          "'$heading' yaml has no '$key:'; a user-invoked skill needs it to route the invocation"
        blocked=1
      fi
    done
  else
    for key in $REQUIRED_TRIGGER; do
      if grep -qE "^$key:[[:space:]]*\S" "$newtop"; then
        warn "$SOURCE" "$hline" dead_field \
          "'$heading' sets '$key:' without disable-model-invocation; it routes nothing"
      fi
    done
  fi
  # a truthy spelling the harness does not act on reads as a gate and is not one
  if grep -qE '^disable-model-invocation:' "$newtop" && ! user_invoked "$newtop"; then
    err "$SOURCE" "$hline" gate_unread \
      "'$heading' sets disable-model-invocation to something other than true; the gate is off"
    blocked=1
  fi

  # the harness truncates description + when_to_use silently past the cap, dropping the clause
  # that says when a skill fires; landing that loss is worse than blocking the export
  wtu=$(field_of "$newtop" when_to_use)
  total=$(( ${#desc} + ${#wtu} ))
  if [ "$total" -gt "$PEAK" ]; then PEAK=$total; PEAK_LABEL=$label; fi
  if [ "$total" -gt "$LISTING_CAP" ]; then
    err "$SOURCE" "$hline" listing_cap \
      "'$heading' description + when_to_use is $total chars; the listing truncates at $LISTING_CAP"
    blocked=1
  elif [ "$total" -gt "$LISTING_WARN" ]; then
    warn "$SOURCE" "$hline" listing_budget \
      "'$heading' description + when_to_use is $total chars, inside $LISTING_WARN of a $LISTING_CAP cap"
  fi

  fi

  fi

  if [ ! -f "$skill" ]; then
    err "$skill" 1 missing_file "the map names it and nothing is there; scaffold the skill first"
    BLOCKED=$((BLOCKED + 1))
    continue
  fi
  if ! is_script "$skill" && [ "$(sed -n '1p' "$skill")" != '---' ]; then
    err "$skill" 1 skill_no_frontmatter "line 1 is not ---, so the managed region has no shape"
    BLOCKED=$((BLOCKED + 1))
    continue
  fi

  boundary=$(region_end "$skill")
  curtop="$SCRATCH/$pair.curtop"
  sed -n "1,$((boundary - 1))p" "$skill" | strip_trailing > "$curtop"

  if cmp -s "$curtop" "$newtop"; then
    IN_SYNC=$((IN_SYNC + 1))
    continue
  fi
  DRIFTED=$((DRIFTED + 1))

  # which half moved: both tops open with ---, so the second --- splits them the same way; a
  # script has no such split, so its whole file is the one region a row can name
  region='frontmatter+preamble'
  if is_script "$skill"; then
    region='file'
  else
    close_cur=$(awk 'NR > 1 && $0 == "---" { print NR; exit }' "$curtop")
    close_new=$(awk 'NR > 1 && $0 == "---" { print NR; exit }' "$newtop")
    if [ -n "$close_cur" ] && [ -n "$close_new" ]; then
      fm_same=0; pre_same=0
      cmp -s <(sed -n "1,${close_cur}p" "$curtop") <(sed -n "1,${close_new}p" "$newtop") && fm_same=1
      cmp -s <(sed -n "$((close_cur + 1)),\$p" "$curtop") <(sed -n "$((close_new + 1)),\$p" "$newtop") && pre_same=1
      if [ "$fm_same" -eq 1 ] && [ "$pre_same" -eq 0 ]; then region='preamble'; fi
      if [ "$fm_same" -eq 0 ] && [ "$pre_same" -eq 1 ]; then region='frontmatter'; fi
    fi
  fi
  delta=$(diff "$curtop" "$newtop" | grep -c '^[<>]' || true)

  newer=$(newer_side "$skill")
  printf '%s|%s|%s|%s|%s|%s\n' "$label" "$skill" "$region" "$delta" "$newer" "$pair" >> "$ROWS"
  if [ "$blocked" -eq 1 ]; then
    BLOCKED=$((BLOCKED + 1))
  elif [ "$newer" = copy ]; then
    refuse "$label" "$skill" "$pair"
  else
    printf '%s|%s|%s|%s\n' "$label" "$skill" "$boundary" "$newtop" >> "$QUEUE"
  fi
done < <(jq -r 'to_entries[] | .key as $h
                | (if (.value | type) == "array" then .value[] else .value end)
                | [$h, .] | @tsv' "$MAP")

if [ "$MAPPED" -eq 0 ]; then
  echo "fatal: nothing in $MAP matched ${ONLY[*]:-the map}" >&2; exit 1; fi

# ==============
# COVERAGE
#   a skill or heading the map misses escapes every rule above, so full runs sweep for both
# ==============
if [ ${#ONLY[@]} -eq 0 ]; then
  jq -r '.[] | if type == "array" then .[] else . end' "$MAP" | sort > "$SCRATCH/mapped"
  for doc in plugins/*/skills/*/SKILL.md; do
    [ -f "$doc" ] || continue
    if ! grep -qFx "$doc" "$SCRATCH/mapped"; then
      err "$doc" 1 unmapped_skill "no map entry, so no rule here ever judges this skill's top"
    fi
  done
  # a style copy the map misses is the drift this fan-out exists to stop, so it is an ERROR too
  for style in plugins/*/output-styles/*.md plugins/*/subagent-styles/*.md; do
    [ -f "$style" ] || continue
    if ! grep -qFx "$style" "$SCRATCH/mapped"; then
      err "$style" 1 unmapped_style "no map entry, so this copy can drift from the readme unseen"
    fi
  done
  # a plugin root readme is the same fan-out again, and a stale one is the copy a marketplace
  # install actually shows, so an unmapped one is the same failure
  for copy in plugins/*/README.md; do
    [ -f "$copy" ] || continue
    if ! grep -qFx "$copy" "$SCRATCH/mapped"; then
      err "$copy" 1 unmapped_readme "no map entry, so this copy can drift from the readme unseen"
    fi
  done
  # a hook action with no doc, or a doc the map misses, escapes every rule above; pairing each
  # action script to a mapped doc is what makes an undocumented action an error rather than drift
  for action in plugins/*/hooks/*/*.sh; do
    [ -f "$action" ] || continue
    doc="${action%.sh}.md"
    if [ ! -f "$doc" ]; then
      err "$action" 1 undocumented_action "no $(basename "$doc") beside it; every action carries its doc"
      continue
    fi
    if ! grep -qFx "$doc" "$SCRATCH/mapped"; then
      err "$doc" 1 unmapped_hookdoc "no map entry, so this doc can drift from the readme unseen"
    fi
  done
  # catalog headings live between '## Plugins & Skills' and the next h2; one heading, one entry
  while IFS= read -r found; do
    [ -n "$found" ] || continue
    if ! jq -e --arg h "$found" 'has($h)' "$MAP" >/dev/null 2>&1; then
      warn "$SOURCE" "$(heading_line "$found")" unmapped_heading \
        "'$found' sits in the catalog and the map never names it"
    fi
  done < <(awk '/^## Plugins & Skills$/ { insec = 1; next }
                insec && /^## / { exit }
                insec && /^```/ { fence = !fence; next }
                insec && !fence && /^#### / { print }' "$SOURCE")
fi

# ==============
# TELEMETRY
# ==============
ERRORS=$(grep -c '^ERROR|' "$FINDINGS" || true)
WARNINGS=$(grep -c '^WARN|' "$FINDINGS" || true)
MODE='export'
if [ "$CHECK" -eq 1 ]; then MODE='check (nothing written)'; fi

# one file per day: the count is read off the headings already in it, so the number the agent
# writes survives a run that reported nothing. `grep -c` exits 1 on no match, hence the `|| true`
TODAYS_AUDIT="$ARTIFACTS/$(date +%Y-%m-%d).md"
if [ -f "$TODAYS_AUDIT" ];
then AUDIT_COUNT=$(grep -c '^## Export Audit #' "$TODAYS_AUDIT" || true)
else AUDIT_COUNT=0; fi
AUDIT_COUNT=${AUDIT_COUNT:-0}

cat <<EOF

=== /export-readme telemetry ===
source: $SOURCE
map: $MAP
audit_file: $TODAYS_AUDIT
audit_count: $AUDIT_COUNT
next_audit: $((AUDIT_COUNT + 1))
timestamp: $(date '+%Y-%m-%d %H:%M')
mapped: $MAPPED target(s)
in_sync: $IN_SYNC
drift: $DRIFTED
blocked: $BLOCKED
listing: $PEAK/$LISTING_CAP chars at its widest ($PEAK_LABEL)
errors: $ERRORS
warnings: $WARNINGS
mode: $MODE
--- drift ---
EOF

if [ "$DRIFTED" -eq 0 ]; then
  echo "none — every managed region matches its readme section"
else
  printf '%-22s %-22s %-6s %-7s %s\n' 'SKILL' 'REGION' 'DELTA' 'NEWER' 'FILE'
  awk -F'|' '{ printf "%-22s %-22s %-6s %-7s %s\n", $1, $3, $4, $5, $2 }' "$ROWS"
fi

if [ "$ERRORS" -gt 0 ] || [ "$WARNINGS" -gt 0 ]; then
  echo "--- findings ---"
  sort -t'|' -k1,1 -k2,2 -k3,3n "$FINDINGS" \
    | awk -F'|' '{ printf "%-5s %-14s %-19s %s\n", $1, $2 ":" $3, $4, $5 }'
fi

# only the refused rows print a diff: that edit is the one about to be lost, and every other row
# is the readme doing exactly what it is meant to do
if [ -s "$REFUSED" ]; then
  while IFS='|' read -r label skill pair; do
    [ -n "$pair" ] || continue
    echo "--- refused: $label (the copy moved after $SOURCE) ---"
    # a readme copy rendered nothing into scratch, and an absent one has no left side at all
    if is_readme "$skill"; then
      have=$skill
      if [ ! -f "$have" ]; then have=$EMPTY; fi
      diff -u -L "$skill (copy)" -L "$SOURCE (source)" "$have" "$SOURCE" || true
    else
      diff -u -L "$skill (managed region)" -L "$SOURCE (rendered)" \
        "$SCRATCH/$pair.curtop" "$SCRATCH/$pair.newtop" || true
    fi
  done < "$REFUSED"
fi

# ==============
# EXPORT
#   pass two rewrites each unblocked drifted region; a blocked one was already reported above
# ==============
EXPORTED=0
if [ "$CHECK" -eq 0 ]; then
  EXPORTED=$(grep -c . "$QUEUE" || true)
  echo "--- export ---"
  if [ "$EXPORTED" -eq 0 ]; then
    echo "nothing to write: no unblocked drift"
  fi
  while IFS='|' read -r label skill boundary newtop; do
    [ -n "$label" ] || continue
    # boundary 0 is the whole-file copy: cp, because the render below strips trailing blanks
    # and would land a file that is one byte off the source it claims to be identical to
    if [ "$boundary" -eq 0 ]; then
      cp "$newtop" "$skill"
    else
      out="$SCRATCH/out"
      { cat "$newtop"; echo; sed -n "${boundary},\$p" "$skill"; } > "$out"
      strip_trailing "$out" > "$skill"
    fi
    printf 'wrote %s (%s)\n' "$skill" "$label"
  done < "$QUEUE"
  if [ "$EXPORTED" -gt 0 ]; then
    echo "exported: $EXPORTED file(s); re-run with --check to confirm in_sync"
  fi
fi

cat <<'EOF'
--- needs a human ---
- the readme is the source of truth: reconcile INTO the readme, never by hand-editing a copy
- an ERROR names a section that did not export; fix the readme line the finding points at
- a copy_newer refusal is a skill-side edit: move it into its readme section, then re-run
- --check writes nothing, which is the mode ci runs and the one to read a drift table from
========================
EOF

if [ "$ERRORS" -gt 0 ]; then exit 1; fi
if [ "$CHECK" -eq 1 ] && [ "$DRIFTED" -gt 0 ]; then exit 1; fi
exit 0

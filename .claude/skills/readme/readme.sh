#!/bin/bash
# ==============================================
# @file readme.sh - readme to skill-top exporter
# ==============================================
# @description
# SOURCE
# - the readme's catalog is the source of truth for every skill's frontmatter and preamble
# - each mapped `#### <Skill>` section carries a yaml fence, then the preamble that follows it
# - `map.json` beside this file names which readme heading feeds which SKILL.md
# - a map value may be a list, so one section exports into every copy that has to agree
# REGION
# - a skill's managed region runs from line 1 to the first body heading after its frontmatter
# - a style file has no such heading, so its whole file is the region and the export owns it
# - export replaces that region with the section's yaml inner block plus its trailing markdown
# - the bare invocation fence above the yaml block is readme display sugar and never lands
# CHECKS
# - every frontmatter rule lives here now, judged at the readme source before anything lands
# - required fields: name, license, compatibility, description; triggers add model and effort
# - `metadata.kind` is declared; a trigger sets disable-model-invocation: true, a spec must not
# - `description` holds 100-110 chars; description + when_to_use stays under the 1536 listing cap
# - `name` must match the skill's folder, and every SKILL.md on disk must appear in the map
# - a style target earns name and description only; the rest route an invocation it never has
# - any ERROR on a section blocks that one skill's export and never the others
# RUN
# - check is the default: prints the drift table, writes nothing, exits 1 on drift or ERROR
# - `--diff` appends a unified diff per drifted skill; `--apply` rewrites the managed regions
# - `--apply` prompts on a tty; an agent confirms in chat first, then re-runs with `--yes`
# - pass skill names to scope either mode; `--map`/`--source` swap the config for tests
# @see .claude/skills/readme/map.json, .claude/skills/readme/SKILL.md, .claude/skills/skills/skills.sh, README.md
set -euo pipefail

STRICT=0
APPLY=0
DIFF=0
YES=0
KEEP=0
MAP=".claude/skills/readme/map.json"
SOURCE="README.md"
REQUIRED="name license compatibility description"
# a style carries no license, no compatibility and no kind; it is a prompt, not an invocation
REQUIRED_STYLE="name description"
# model and effort route an invocation, so only a trigger needs them; on a spec they are dead config
REQUIRED_TRIGGER="model effort"
DESC_MIN=100
DESC_MAX=110
# the harness truncates `description` + `when_to_use` at this many characters in the skill listing
LISTING_CAP=1536
# 80% of the cap: near enough that the next edit is the one that drops text without saying so
LISTING_WARN=1228

ONLY=()
while [ $# -gt 0 ]; do
  case "$1" in
    --apply) APPLY=1;;
    --diff) DIFF=1;;
    --strict) STRICT=1;;
    --yes) YES=1;;
    --keep) KEEP=1;;
    --map) MAP=${2:?fatal: --map needs a path}; shift;;
    --source) SOURCE=${2:?fatal: --source needs a path}; shift;;
    -h|--help) sed -n '2,24p' "$0"; exit 0;;
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
cleanup() { st=$?; if [ "$KEEP" -eq 0 ]; then rm -rf "$SCRATCH"; fi; exit "$st"; }
trap cleanup EXIT

# findings collect as "SEV|file|line|category|detail"; drift rows as "label|path|region|delta"
FINDINGS="$SCRATCH/findings"
ROWS="$SCRATCH/rows"
QUEUE="$SCRATCH/queue"
: > "$FINDINGS"; : > "$ROWS"; : > "$QUEUE"

err()  { printf 'ERROR|%s|%s|%s|%s\n' "$1" "$2" "$3" "$4" >> "$FINDINGS"; }
warn() { printf 'WARN|%s|%s|%s|%s\n' "$1" "$2" "$3" "$4" >> "$FINDINGS"; }

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

# one frontmatter value, quotes shed, folded scalars unwrapped; mirrors skills.sh
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

# an output style is mapped like a skill and checked like almost nothing: it carries no kind, no
# invocation and no listing entry, so the fields that route one are dead config on it
is_style() {
  case "$1" in */output-styles/*.md) return 0;; *) return 1;; esac
}

# metadata.kind, declared rather than guessed; empty when unset, mirrors skills.sh
kind_of() {
  awk '/^metadata:/ { inside = 1; next }
       inside && /^[^[:space:]]/ { inside = 0 }
       inside && /^[[:space:]]+kind:/ { gsub(/^[[:space:]]+kind:[[:space:]]*/, ""); print; exit }' "$1"
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
  # a skill owns a folder and every doc is called SKILL.md; a style is one file and owns its name
  if is_style "$skill"; then name=$(basename "$skill" .md)
  else name=$(basename "$(dirname "$skill")"); fi
  plugin=$(plugin_of "$skill")
  label=${plugin:+$plugin:}$name
  in_scope "$name" "$label" || continue
  MAPPED=$((MAPPED + 1))
  pair=$((pair + 1))
  blocked=0

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
  render_top "$section" | strip_trailing > "$newtop"

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
  if is_style "$skill"; then required=$REQUIRED_STYLE; fi
  for key in $required; do
    if ! grep -qE "^$key:[[:space:]]*\S" "$newtop"; then
      err "$SOURCE" "$hline" missing_field "'$heading' yaml has no '$key:'; the field is required"
      blocked=1
    fi
  done

  # a style is not listed, not invoked and has no kind, so the rules below judge fields it would
  # never carry; everything after them is the drift compare, which is why a style is mapped at all
  if is_style "$skill"; then
    desc=''
    wtu=''
  else

  desc=$(field_of "$newtop" description)
  if [ -n "$desc" ]; then
    if [ ${#desc} -lt "$DESC_MIN" ] || [ ${#desc} -gt "$DESC_MAX" ]; then
      warn "$SOURCE" "$hline" description_length \
        "'$heading' description is ${#desc} chars; the band is $DESC_MIN-$DESC_MAX"
    fi
  fi

  # the kind decides the rest of the frontmatter, so an undeclared one cannot export
  kind=$(kind_of "$newtop")
  case "$kind" in
    trigger)
      for key in $REQUIRED_TRIGGER; do
        if ! grep -qE "^$key:[[:space:]]*\S" "$newtop"; then
          err "$SOURCE" "$hline" missing_field "'$heading' yaml has no '$key:'; a trigger needs it"
          blocked=1
        fi
      done
      if ! grep -qE '^disable-model-invocation:[[:space:]]*(true|yes|on|1)[[:space:]]*$' "$newtop"; then
        err "$SOURCE" "$hline" trigger_ungated \
          "'$heading' is kind: trigger with no 'disable-model-invocation: true'; prose is not a gate"
        blocked=1
      fi;;
    spec)
      if grep -qE '^disable-model-invocation:' "$newtop"; then
        err "$SOURCE" "$hline" spec_gated \
          "'$heading' is kind: spec, which auto-loads; drop disable-model-invocation"
        blocked=1
      fi;;
    *)
      err "$SOURCE" "$hline" no_kind "'$heading' yaml needs metadata with 'kind: trigger' or 'kind: spec'"
      blocked=1;;
  esac

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

  if [ ! -f "$skill" ]; then
    err "$skill" 1 missing_file "the map names it and nothing is there; scaffold the skill first"
    BLOCKED=$((BLOCKED + 1))
    continue
  fi
  if [ "$(sed -n '1p' "$skill")" != '---' ]; then
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

  # which half moved: both tops open with ---, so the second --- splits them the same way
  close_cur=$(awk 'NR > 1 && $0 == "---" { print NR; exit }' "$curtop")
  close_new=$(awk 'NR > 1 && $0 == "---" { print NR; exit }' "$newtop")
  region='frontmatter+preamble'
  if [ -n "$close_cur" ] && [ -n "$close_new" ]; then
    fm_same=0; pre_same=0
    cmp -s <(sed -n "1,${close_cur}p" "$curtop") <(sed -n "1,${close_new}p" "$newtop") && fm_same=1
    cmp -s <(sed -n "$((close_cur + 1)),\$p" "$curtop") <(sed -n "$((close_new + 1)),\$p" "$newtop") && pre_same=1
    if [ "$fm_same" -eq 1 ] && [ "$pre_same" -eq 0 ]; then region='preamble'; fi
    if [ "$fm_same" -eq 0 ] && [ "$pre_same" -eq 1 ]; then region='frontmatter'; fi
  fi
  delta=$(diff "$curtop" "$newtop" | grep -c '^[<>]' || true)

  printf '%s|%s|%s|%s|%s\n' "$label" "$skill" "$region" "$delta" "$pair" >> "$ROWS"
  if [ "$blocked" -eq 1 ]; then
    BLOCKED=$((BLOCKED + 1))
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
  for style in plugins/*/output-styles/*.md; do
    [ -f "$style" ] || continue
    if ! grep -qFx "$style" "$SCRATCH/mapped"; then
      err "$style" 1 unmapped_style "no map entry, so this copy can drift from the readme unseen"
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
MODE='check (nothing written)'
if [ "$APPLY" -eq 1 ]; then MODE='apply'; fi

cat <<EOF

=== /readme telemetry ===
source: $SOURCE
map: $MAP
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
  printf '%-22s %-22s %-6s %s\n' 'SKILL' 'REGION' 'DELTA' 'FILE'
  awk -F'|' '{ printf "%-22s %-22s %-6s %s\n", $1, $3, $4, $2 }' "$ROWS"
fi

if [ "$ERRORS" -gt 0 ] || [ "$WARNINGS" -gt 0 ]; then
  echo "--- findings ---"
  sort -t'|' -k1,1 -k2,2 -k3,3n "$FINDINGS" \
    | awk -F'|' '{ printf "%-5s %-14s %-19s %s\n", $1, $2 ":" $3, $4, $5 }'
fi

if [ "$DIFF" -eq 1 ] && [ "$DRIFTED" -gt 0 ]; then
  while IFS='|' read -r label skill region delta pair; do
    [ -n "$pair" ] || continue
    echo "--- diff: $label ---"
    diff -u -L "$skill (managed region)" -L "$SOURCE (rendered)" \
      "$SCRATCH/$pair.curtop" "$SCRATCH/$pair.newtop" || true
  done < "$ROWS"
fi

# ==============
# APPLY
#   pass two rewrites each unblocked drifted region, only after an explicit confirmation
# ==============
if [ "$APPLY" -eq 1 ]; then
  TODO=$(grep -c . "$QUEUE" || true)
  if [ "$TODO" -eq 0 ]; then
    echo "--- apply ---"
    echo "nothing to write: no unblocked drift"
  else
    if [ "$YES" -ne 1 ]; then
      if [ -t 0 ]; then
        printf 'rewrite %s managed region(s) from %s? [y/N] ' "$TODO" "$SOURCE"
        read -r reply
        case "$reply" in y|Y|yes|YES) ;; *) echo "aborted: nothing written"; exit 1;; esac
      else
        echo "fatal: --apply with no tty needs --yes; confirm the drift table first" >&2
        exit 1
      fi
    fi
    echo "--- apply ---"
    while IFS='|' read -r label skill boundary newtop; do
      [ -n "$label" ] || continue
      out="$SCRATCH/out"
      { cat "$newtop"; echo; sed -n "${boundary},\$p" "$skill"; } > "$out"
      strip_trailing "$out" > "$skill"
      printf 'wrote %s (%s)\n' "$skill" "$label"
    done < "$QUEUE"
    echo "applied: $TODO file(s); re-run without --apply to confirm in_sync"
  fi
fi

cat <<'EOF'
--- needs a human (before --apply) ---
- the readme is the source of truth: reconcile INTO the readme, never by hand-editing a skill top
- a skill-side edit worth keeping moves into its readme section first, then the export re-lands it
- an ERROR names a section that will not export; fix the readme line the finding points at
- confirm the drift table in chat, then re-run with --apply (add skill names for a partial sync)
========================
EOF

if [ "$ERRORS" -gt 0 ]; then exit 1; fi
if [ "$STRICT" -eq 1 ] && [ "$WARNINGS" -gt 0 ]; then exit 1; fi
if [ "$APPLY" -eq 0 ] && [ "$DRIFTED" -gt 0 ]; then exit 1; fi
if [ "$APPLY" -eq 1 ] && [ "$BLOCKED" -gt 0 ]; then exit 1; fi
exit 0

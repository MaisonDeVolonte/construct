#!/bin/bash
# ===============================================
# @file setup.sh - the setup wizard and its audit
# ===============================================
# @description
# PAIR
# - sidecar for `/operator:setup` — probes the machine, then routes the reader to the next step
# - `--audit` is the other half, running every lens and merging them into one report
# - safe anytime: read-only by contract, since every lens it runs is read-only by contract
# - the question a bare run answers is position; the question `--audit` answers is coverage
# STATE
# - a bare run prints the state block, the route chooser, then the steps still outstanding
# - a step reads `[done]` only when a probe saw it, so nothing is ever claimed on trust
# - every probe degrades to `not observable` rather than failing, since a deny rule is not a fault
# - jq is probed rather than required, because the reader most likely to lack it is the new one
# AUDIT
# - it invokes, preserves and correlates; no lens verdict is ever recomputed here
# - each lens output is kept whole, so the merged report can be checked against the raw text
# - a lens that fails to complete is an ERROR, never a zero: silence is the fault it looks for
# - counts are read from the telemetry a lens prints; a lens that prints none reads as ungraded
# LENSES
# - `settings` files, `permissions` gate, `hooks` registration, `scripts` commands
# - then `credentials` masks, `context` boundary, `upstream` feed
# - every run is all seven in that order, since the lenses build on each other as they read
# - no flag narrows it: one lens belongs to its own skill, under its own artifact
# PREFLIGHT
# - install stays with the reader: a skill cannot install the plugin that carries it
# - it detects which of the three install routes is live, and names the one it found
# - the audit hard requires jq and a git repo, since it grades files the wizard only counts
# RUN
# - `--roadmap` reprints the saved roadmap without probing, which is how a session resumes
# - `--audit` prices the pass and stops, since replaying every extracted command costs minutes
# - `--confirm` is what releases that run, and `scripts` owns most of the seconds it spends
# - `-h` exits before anything runs, and the doc's `## Help` section is what answers it
# - the doc appends one entry to the day's roadmap, or to the day's audit under `--audit`
# @see plugins/operator/skills/setup/SKILL.md, .construct/operator/setup/

set -euo pipefail

# the doc is read only after this has already run, so help is refused here or not at all; the doc's
# own '## Help' section owns the output, which is why this prints a marker rather than a usage text
case " $* " in *" --help "*|*" -h "*) echo "help: requested"; exit 0;; esac

# ==============
# PREFLIGHT
# ==============
# every flag names a mode this sidecar enters instead of the wizard, and the wizard is what a bare
# run does; a lens name is the likely miss, so the fatal points at the sibling that owns it
ROADMAP_ONLY=0
AUDIT=0
CONFIRM=0
while [ $# -gt 0 ]; do
  case "$1" in
    --roadmap) ROADMAP_ONLY=1;;
    --audit) AUDIT=1;;
    --confirm) CONFIRM=1;;
    *) echo "fatal: unknown flag $1; reach for /operator:${1#--} if it names a lens" >&2; exit 1;;
  esac
  shift
done

ROADMAP_DIR=".construct/operator/setup/roadmap"
AUDIT_DIR=".construct/operator/setup/audit"

# ==============
# AUDIT - invoke, preserve, never regrade
# ==============
# the lenses sit one folder over in skills/: resolve from this file before any cd, since BASH_SOURCE
# arrives relative and cwd holds no plugins/operator/ once installed from a marketplace
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)

# fixed and complete: a lens flag here would run a sibling's sidecar under this skill's artifact,
# filing a narrower report than `/operator:<lens>` under a heading that claims the whole stack
LENSES=(settings permissions hooks scripts credentials context upstream)
LENS_STATUS=()
LENS_SECONDS=()

err()  { printf 'ERROR|%s|%s|%s\n' "$1" "$2" "$3" >> "$FINDINGS"; }
warn() { printf 'WARN|%s|%s|%s\n'  "$1" "$2" "$3" >> "$FINDINGS"; }
pass() { printf 'PASS|%s|%s|%s\n'  "$1" "$2" "$3" >> "$FINDINGS"; }

count_of() {
  printf '%s' "$1" | sed -n "s/^$2: \([0-9]\{1,\}\)\$/\1/p" | head -n 1
}

run_lens() {
  local lens=$1 script output code started elapsed errors warnings
  script="$HERE/../$lens/$lens.sh"
  if [ ! -f "$script" ]; then
    err suite "$lens" "no $lens.sh in skills/$lens, so this lens never ran"
    LENS_STATUS+=("$lens|missing|-|-")
    LENS_SECONDS+=("$lens|0")
    return
  fi

  started=$SECONDS
  set +e
  output=$(bash "$script" 2>&1)
  code=$?
  set -e
  elapsed=$((SECONDS - started))
  printf '%s\n' "$output" > "$SCRATCH/$lens.out"
  LENS_SECONDS+=("$lens|$elapsed")

  errors=$(count_of "$output" errors)
  warnings=$(count_of "$output" warnings)

  # no count in the output means the lens exited before its telemetry, so its verdict is unknown.
  # reporting that as zero is the fail-open this branch exists to refuse
  if [ -z "$errors" ]; then
    err suite "$lens" "exited $code in ${elapsed}s printing no error count, so it is ungraded"
    LENS_STATUS+=("$lens|ungraded|-|-")
    return
  fi

  warnings=${warnings:-0}
  LENS_STATUS+=("$lens|graded|$errors|$warnings")
  if [ "$errors" -gt 0 ]; then
    err "$lens" errors "$errors error(s) in ${elapsed}s; the detail is in this lens's block below"
  else
    pass "$lens" errors "0 errors in ${elapsed}s"
  fi
  if [ "$warnings" -gt 0 ]; then
    warn "$lens" warnings "$warnings warning(s); each one is a judgement call in the block below"
  fi
}

# the audit's own dated artifact, graded here so nothing outside this file decides its shape
# it keeps a tree of its own, since the roadmap beside it grades by a different set of rules
ARTIFACT_KIND="suite"
ARTIFACT_SECTIONS=$'state\nfindings\nresolutions\ntelemetry'
ARTIFACT_LABELS='(Settings|Permissions|Scripts|Credentials|Upstream|Suite)/[A-Za-z ]+'
ARTIFACT_MAX_WIDTH=100

# this branch reports "category|scope|detail", so location folds into the scope field
artifact_err()  { err "$3" "$1:$2" "$4"; }
artifact_warn() { warn "$3" "$1:$2" "$4"; }

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
  local expected=1 previous='' count=0 found=0 fixed=0 lineno text infence=0 blocks=0

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
    # heading to the file, so a settings entry in the suite file is caught rather than merged
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
        artifact_err "$rel" "$lineno" finding_shape 'findings read "- **Lens/Label** — what is wrong, and on what"'
        continue
      fi
      label=$(printf '%s' "$text" | sed -n 's/^- \*\*\([^*]*\)\*\*.*/\1/p')
      # every finding names the lens it came from, since a merged report with unattributed
      # findings cannot be checked back against the block it was read out of
      if ! printf '%s' "$label" | grep -qE "^($ARTIFACT_LABELS)\$"; then
        artifact_warn "$rel" "$lineno" finding_label "'$label' is not <Lens>/<Label> for a lens this audit runs"
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
      artifact_err "$rel" "$start" telemetry "telemetry holds the raw lens output, never blank"
      continue
    fi

    # the audit always runs every lens, so a missing block means an entry claiming the whole stack
    # while holding less; that is an error rather than a note, since no flag can narrow this run
    blocks=$(printf '%s' "$body" | grep -c '^```' || true)
    if [ "$blocks" -lt 2 ]; then
      artifact_warn "$rel" "$start" telemetry "fence the raw output, so a reader can tell it from prose"
    fi
    for lens in "${LENSES[@]}"; do
      printf '%s' "$body" | grep -q "^#### $lens\$" && continue
      artifact_err "$rel" "$start" telemetry_lens "no '#### $lens' block; every entry holds all 5"
    done
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

if [ "$AUDIT" -eq 1 ]; then
  # priced and gated before any lens runs, for the same reason help is refused above: the doc is
  # read only once this has already returned, and `scripts` owns almost all of the minutes
  ESTIMATE_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo .)
  ESTIMATE_SCALE=$({ find "$ESTIMATE_ROOT/plugins" -path '*/skills/*/*.sh' 2>/dev/null || true; } | wc -l | tr -d ' ')
  echo "estimate: scales with the ${ESTIMATE_SCALE:-0} sidecars the scripts lens replays command by command"
  if [ "$CONFIRM" -eq 0 ]; then echo "confirm: required"; exit 0; fi

  # the wizard probes these and reports what is missing; the audit grades files, so it refuses
  if ! command -v jq >/dev/null 2>&1; then echo "fatal: jq is required" >&2; exit 1; fi
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "fatal: not a git repository" >&2; exit 1; fi

  cd "$(git rev-parse --show-toplevel)"
  ROOT=$(pwd)

  # repo-local scratch: the sandbox denies writes outside cwd, and macos mktemp ignores TMPDIR
  TMPROOT="$ROOT/tmp"
  mkdir -p "$TMPROOT"
  FINDINGS=$(mktemp "$TMPROOT/suiteaudit-findings.XXXXXX")
  SCRATCH=$(mktemp -d "$TMPROOT/suiteaudit-scratch.XXXXXX")
  cleanup() { st=$?; if [ "$st" -eq 0 ]; then rm -rf "$FINDINGS" "$SCRATCH"; fi; }
  trap cleanup EXIT

  SUITE_START=$SECONDS
  for lens in "${LENSES[@]}"; do run_lens "$lens"; done
  SUITE_ELAPSED=$((SECONDS - SUITE_START))

  check_artifact "$AUDIT_DIR"

  ERRORS=$(grep -c '^ERROR|' "$FINDINGS" 2>/dev/null || true)
  WARNINGS=$(grep -c '^WARN|' "$FINDINGS" 2>/dev/null || true)
  PASSES=$(grep -c '^PASS|' "$FINDINGS" 2>/dev/null || true)
  ERRORS=${ERRORS:-0}
  WARNINGS=${WARNINGS:-0}
  PASSES=${PASSES:-0}

  TODAYS_AUDIT="$AUDIT_DIR/$(date +%Y-%m-%d).md"
  if [ -f "$ROOT/$TODAYS_AUDIT" ];
  then AUDIT_COUNT=$(grep -c '^## Suite Audit #' "$ROOT/$TODAYS_AUDIT" || true)
  else AUDIT_COUNT=0; fi
  AUDIT_COUNT=${AUDIT_COUNT:-0}

cat <<EOF

=== setup.sh sidecar (audit) ===
audit_file: $TODAYS_AUDIT
audit_count: $AUDIT_COUNT
next_audit: $((AUDIT_COUNT + 1))
timestamp: $(date '+%Y-%m-%d %H:%M')
lenses: ${#LENSES[@]} run in ${SUITE_ELAPSED}s
passes: $PASSES
errors: $ERRORS
warnings: $WARNINGS
--- lenses ---
EOF

  # the roll-up names every lens and how it ended, so a lens that never ran cannot read as clean
  for row in "${LENS_STATUS[@]}"; do
    IFS='|' read -r lens state lens_errors lens_warnings <<< "$row"
    secs=0
    for timed in "${LENS_SECONDS[@]}"; do
      case "$timed" in "$lens|"*) secs=${timed#*|};; esac
    done
    printf '%-12s %-9s errors=%-4s warnings=%-4s %ss\n' \
      "$lens" "$state" "$lens_errors" "$lens_warnings" "$secs"
  done

  printf -- '--- findings ---\n'
  sort -t'|' -k2,2 -k3,3 "$FINDINGS" \
    | awk -F'|' '{ printf "%-5s %-12s %-30s %s\n", $1, $2, $3, $4 }'

  # each lens output whole, under a heading the artifact reuses: the merged findings above are only
  # checkable against the text they were read out of
  for lens in "${LENSES[@]}"; do
    [ -f "$SCRATCH/$lens.out" ] || continue
    printf '\n--- %s (verbatim) ---\n' "$lens"
    cat "$SCRATCH/$lens.out"
  done

cat <<'EOF'

--- needs a human (rules no script can judge) ---
- an ungraded lens is the finding that outranks every count, since that lens answered nothing
- a lens verdict is that lens's to make; this audit never overrules one, it only collects them
- read a settings verbs error against the permissions allow list, since one makes the other live
- a scripts no-match is a gap in the corpus as often as a gap in the rules
- the audit proves today's stack; an upgrade can move the boundary with no file changing
================================
EOF

  if [ "$ERRORS" -gt 0 ]; then exit 1; fi
  exit 0
fi

# ==============
# WIZARD - what a bare run does, and the only path that never costs a turn
# ==============
# a missing tool is the finding this wizard exists to report, so it is probed and never required
JQ=0; command -v jq >/dev/null 2>&1 && JQ=1
GIT=0; command -v git >/dev/null 2>&1 && GIT=1
CURL=0; command -v curl >/dev/null 2>&1 && CURL=1

# a reader part-way through install has no repo yet, so the roadmap follows cwd until one exists
ROOT=$PWD
if [ "$GIT" -eq 1 ] && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  ROOT=$(git rev-parse --show-toplevel)
  cd "$ROOT"
fi

USER_SCOPE="$HOME/.claude/settings.json"
PROJECT_SCOPE="$ROOT/.claude/settings.json"
LOCAL_SCOPE="$ROOT/.claude/settings.local.json"
MANAGED_SCOPE="/Library/Application Support/ClaudeCode/managed-settings.json"

TODO=0
step() {
  # "[done]" is only ever printed from a probe, so an unreadable scope reads as work instead
  if [ "$1" = "have" ]; then printf '%-2s [done] %-11s %s\n' "$2" "$3" "$4"
  else TODO=$((TODO + 1)); printf '%-2s [todo] %-11s %s\n' "$2" "$3" "$4"; fi
}

# a scope this sidecar cannot read is reported as unreadable: a deny rule working is not a gap
jq_query() {
  local file=$1 filter=$2
  [ "$JQ" -eq 1 ] || return 1
  [ -f "$file" ] || return 1
  jq -e "$filter" "$file" >/dev/null 2>&1
}

# ==============
# STATE - what a probe can see, before any step is named
# ==============
state_deps() {
  local missing=''
  [ "$JQ" -eq 1 ]   || missing="$missing jq"
  [ "$GIT" -eq 1 ]  || missing="$missing git"
  [ "$CURL" -eq 1 ] || missing="$missing curl"
  if [ -n "$missing" ]; then
    printf 'deps       MISSING%s, so step 1 comes before everything below\n' "$missing"
  else
    printf 'deps       bash %s, jq %s, git and curl all present\n' \
      "${BASH_VERSION%%(*}" "$(jq --version 2>/dev/null | sed 's/^jq-//')"
  fi
}

# three install routes leave three different traces, so the trace is what names the route
state_route() {
  local link
  if [ -L "$HOME/.claude/skills/operator" ]; then
    link=$(readlink "$HOME/.claude/skills/operator" 2>/dev/null || echo '?')
    printf 'route      clone, symlinked from %s\n' "$link"
  elif jq_query "$PROJECT_SCOPE" '.extraKnownMarketplaces.TheConstruct'; then
    printf 'route      team, TheConstruct pinned in .claude/settings.json\n'
  elif [ -d "$HOME/.claude/plugins/marketplaces/TheConstruct" ]; then
    printf 'route      individual, marketplace installed under ~/.claude/plugins\n'
  elif [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
    printf 'route      running from %s, with no marketplace trace to name it\n' "$CLAUDE_PLUGIN_ROOT"
  else
    printf 'route      no install trace found, so step 2 is where this starts\n'
  fi
}

state_style() {
  local scope
  for scope in "$PROJECT_SCOPE" "$USER_SCOPE"; do
    if jq_query "$scope" '.outputStyle == "operator"'; then
      printf 'style      operator, set in %s\n' "${scope/#$HOME/~}"
      return
    fi
  done
  printf 'style      operator not set in any readable scope, so /config is still a step\n'
}

# the scope table is the whole reason the tiers differ, so it prints every scope every run
state_scopes() {
  local pair name path count found=0
  for pair in "managed:$MANAGED_SCOPE" "user:$USER_SCOPE" "project:$PROJECT_SCOPE" "local:$LOCAL_SCOPE"; do
    name=${pair%%:*}
    path=${pair#*:}
    if [ ! -f "$path" ]; then continue; fi
    found=$((found + 1))
    if [ "$JQ" -eq 1 ] && jq empty "$path" >/dev/null 2>&1; then
      count=$(jq '[.permissions[]?|length]|add // 0' "$path" 2>/dev/null || echo '?')
      printf 'scope      %-8s %s rules\n' "$name" "$count"
    else
      printf 'scope      %-8s present, unparsed from here\n' "$name"
    fi
  done
  [ "$found" -eq 0 ] && printf 'scope      none of the four scopes carry a file yet\n'
  return 0
}

# a sandbox block with no allowedDomains is the shape that breaks a masked token, so both are read
state_sandbox() {
  local scope domains
  for scope in "$USER_SCOPE" "$PROJECT_SCOPE" "$LOCAL_SCOPE"; do
    if jq_query "$scope" '.sandbox'; then
      domains=$(jq '[.sandbox.network.allowedDomains[]?]|length' "$scope" 2>/dev/null || echo '?')
      printf 'sandbox    configured in %s, %s allowed domain(s)\n' "${scope/#$HOME/~}" "$domains"
      return
    fi
  done
  printf 'sandbox    no sandbox block in any readable scope, so no tier is live yet\n'
}

# the credential detail belongs to /operator:settings --advanced; this reads far enough to route
state_creds() {
  local masked=0
  if [ -d "$HOME/.operator" ]; then
    printf 'keydir     present, mode %s\n' "$(stat -f '%Lp' "$HOME/.operator" 2>/dev/null \
      || stat -c '%a' "$HOME/.operator" 2>/dev/null || echo '?')"
  else
    printf 'keydir     absent, so tier 5 has not started\n'
  fi
  if [ "$JQ" -eq 1 ] && [ -f "$USER_SCOPE" ]; then
    masked=$(jq '[.sandbox.credentials.envVars[]?|select(.mode=="mask")]|length' "$USER_SCOPE" 2>/dev/null || echo 0)
  fi
  printf 'masked     %s credential(s) masked in the user scope\n' "$masked"
  if jq_query "$USER_SCOPE" '.sandbox.credentials.files[]?|select(.path|test("\\.construct/\\.env$"))'; then
    printf 'deny       the env file is denied, so no agent reads it back\n'
  else
    printf 'deny       NO deny rule for ~/.construct/.env, which lands before any token does\n'
  fi
}

state_artifact() {
  local today count
  today="$ROADMAP_DIR/$(date +%Y-%m-%d).md"
  if [ -f "$today" ]; then
    count=$(grep -c '^## Setup Roadmap #' "$today" 2>/dev/null || true)
    printf 'roadmap    %s, %s entry(s)\n' "$today" "${count:-0}"
  else
    printf 'roadmap    none today, so this run writes the first entry\n'
  fi
  if [ -d "$AUDIT_DIR" ]; then
    count=$(find "$AUDIT_DIR" -name '*.md' -type f 2>/dev/null | wc -l | tr -d ' ')
    printf 'audits     %s suite audit file(s) under %s\n' "$count" "$AUDIT_DIR"
  else
    printf 'audits     none yet, so --audit has never proved this machine\n'
  fi
}

# ==============
# ROADMAP - the reprint, which resumes a session without spending a probe
# ==============
if [ "$ROADMAP_ONLY" -eq 1 ]; then
  printf '\n=== setup.sh sidecar (roadmap) ===\n'
  printf 'mode       reprint, so nothing below was probed this run\n'
  LATEST=$(find "$ROADMAP_DIR" -name '*.md' -type f 2>/dev/null | sort | tail -n 1 || true)
  if [ -z "$LATEST" ]; then
    printf 'roadmap    no roadmap written yet; run /operator:setup with no flag first\n'
    printf '========================\n'
    exit 0
  fi
  printf 'roadmap    %s\n' "$LATEST"
  printf -- '--- saved roadmap (verbatim) ---\n'
  cat "$LATEST"
  printf '========================\n'
  exit 0
fi

# ==============
# TELEMETRY
# ==============
printf '\n=== setup.sh sidecar ===\n'
printf 'mode       wizard\n'
printf -- '--- state ---\n'
state_deps
state_route
state_style
state_scopes
state_sandbox
state_creds
state_artifact

cat <<'EOF'
--- route (two answers pick one tier) ---
q1 who is this sandbox for: only me / this repo / my team / this whole machine
q2 does this machine hold real credentials an agent could read: yes / no
   only me + no     -> tier 1, then tier 3      (--local, then --user)
   this repo + no   -> tier 2                   (--project)
   my team + no     -> tier 2, committed        (--project)
   this machine     -> tier 4                   (--managed, needs sudo)
   any + yes        -> the tier above, then 5   (--advanced)
EOF

printf -- '--- steps, in this order (each one is yours to run) ---\n'
if [ "$JQ" -eq 1 ] && [ "$GIT" -eq 1 ] && [ "$CURL" -eq 1 ]; then
  step have 1 deps 'jq, git and curl are all on PATH'
else
  step need 1 deps 'install the missing tools above; jq gates every probe below'
fi
if [ -L "$HOME/.claude/skills/operator" ] || [ -d "$HOME/.claude/plugins/marketplaces/TheConstruct" ] \
  || jq_query "$PROJECT_SCOPE" '.extraKnownMarketplaces.TheConstruct'; then
  step have 2 install 'a route was detected above; the readme holds all three'
else
  step need 2 install 'pick option A, B or C in the readme; a skill cannot install its own plugin'
fi
if jq_query "$PROJECT_SCOPE" '.outputStyle == "operator"' || jq_query "$USER_SCOPE" '.outputStyle == "operator"'; then
  step have 3 style 'the operator output style is set'
else
  step need 3 style '/config > Output style > operator'
fi
if [ -f "$LOCAL_SCOPE" ] || [ -f "$PROJECT_SCOPE" ] || [ -f "$USER_SCOPE" ]; then
  step have 4 scope 'at least one settings scope carries a file'
else
  step need 4 scope 'run /operator:settings with the flag your q1 answer picked'
fi
if jq_query "$USER_SCOPE" '.sandbox' || jq_query "$PROJECT_SCOPE" '.sandbox' || jq_query "$LOCAL_SCOPE" '.sandbox'; then
  step have 5 sandbox 'a sandbox block is live; /sandbox prints what the session sees'
else
  step need 5 sandbox 'paste the emitted block, restart the editor, then check /sandbox'
fi
if [ -d "$HOME/.operator" ]; then
  step have 6 credentials 'the key directory exists; /operator:settings --advanced walks the rest'
else
  step need 6 credentials 'tier 5 only: /operator:settings --advanced, one step at a time'
fi
if [ -d "$AUDIT_DIR" ]; then
  step have 7 prove 'a suite audit has run; rerun /operator:setup --audit after any change'
else
  step need 7 prove '/operator:setup --audit --confirm, which spends minutes and grades every lens'
fi

cat <<'EOF'
--- needs a human (rules no script can judge) ---
- only you know who this machine is for, so only you can answer q1 and pick the tier
- a step reading [done] was seen by a probe, and a deny rule can hide a step that is finished
- the managed scope lands outside the project and needs sudo, so it is always your call
- restart the editor between a paste and a check, since the session reads settings once at start
- step 7 costs minutes and is the only step here that proves the others worked
========================
EOF

# the doc numbers its entry from this count, so an absent file has to read as zero rather than blank
TODAYS_ROADMAP="$ROADMAP_DIR/$(date +%Y-%m-%d).md"
if [ -f "$ROOT/$TODAYS_ROADMAP" ];
then ROADMAP_COUNT=$(grep -c '^## Setup Roadmap #' "$ROOT/$TODAYS_ROADMAP" || true)
else ROADMAP_COUNT=0; fi
ROADMAP_COUNT=${ROADMAP_COUNT:-0}

printf 'roadmap_file: %s\n' "$TODAYS_ROADMAP"
printf 'roadmap_count: %s\n' "$ROADMAP_COUNT"
printf 'next_roadmap: %s\n' "$((ROADMAP_COUNT + 1))"
printf 'timestamp: %s\n' "$(date '+%Y-%m-%d %H:%M')"
printf 'todo: %s\n' "$TODO"
exit 0

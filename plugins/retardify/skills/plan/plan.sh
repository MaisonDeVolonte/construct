#!/bin/bash
# ==============================================================================
# @file plan.sh - staged plan sidecar: names the target, then grades what landed
# ==============================================================================
# @description
# PAIR
# - the only sidecar for `/retardify:plan`, which owns both halves of its own artifact
# - the doc carries the shape; this file names where it lands and grades what landed there
# - one skill is one SKILL.md and one sidecar, so nothing outside this pair decides its shape
# RUN
# - no flag runs the trigger half, so every existing invocation is unchanged
# - a path argument is a source document, and it stops the run on `confirm: required`
# - the doc asks in chat and the user says go, since the goal and the filename were derived
# - `--confirm` on the invocation skips that stop for anyone who already knows the answer
# - `--check [paths]` runs the validator half; with no paths it grades the whole artifact dir
# - ERROR breaks a rule the doc states outright; WARN names a smell the doc tolerates
# @see plugins/retardify/skills/plan/SKILL.md, .construct/retardify/plan/, plugins/retardify/skills/graph/SKILL.md, plugins/retardify/skills/log/SKILL.md, plugins/retardify/shared/secrets.sh

set -euo pipefail

# the doc is read only after this has already run, so help is refused here or not at all; the doc's
# own '## Help' section owns the output, which is why this prints a marker rather than a usage text
case " $* " in *" --help "*|*" -h "*) echo "help: requested"; exit 0;; esac

# `--check` selects the validator half; anything else is the trigger, so the doc's own
# bang-injected call keeps working untouched
if [ "${1:-}" = "--check" ]; then
  shift
else
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "fatal: not a git repository" >&2; exit 1; fi
  cd "$(git rev-parse --show-toplevel)"

  ARTIFACTS=".construct/retardify/plan"
  TEMPLATE="plugins/retardify/skills/plan/SKILL.md"
  VALIDATOR="plugins/retardify/skills/plan/plan.sh --check"
  TODAY=$(date +%Y-%m-%d)

  # the harness passes $ARGUMENTS as one quoted word, so a flag inside it arrives as plain text
  ARGS="$*"
  CONFIRMED=0
  case " $ARGS " in *" --confirm "*) CONFIRMED=1;; esac
  ARGS=$(printf '%s' "$ARGS" \
    | sed -e 's/--confirm//g' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

  # a path is a source document rather than a goal, so the goal is read out of the file
  # any readable file qualifies, since a research brief is promoted into a plan the same way
  SPEC=none
  SPEC_KIND=none
  BASE=""
  STEM=""
  if [ -f "$ARGS" ]; then
    SPEC="$ARGS"
    BASE=$(basename "$SPEC")
    STEM=$(printf '%s' "$BASE" | sed -e 's/\.[A-Za-z0-9]\{1,\}$//' \
      -e 's/^[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}-//' -e 's/^operation-//')
  fi

  # a goal is prose, so one word carrying a slash or an extension was meant to be a path
  # reading it as a goal would name the plan after the typo and then plan the wrong work
  if [ "$SPEC" = none ]; then
    case "$ARGS" in
      *[[:space:]]*) ;;
      */*|*.*) echo "fatal: no such file: $ARGS" >&2; exit 1;;
    esac
  fi

  GOAL="$ARGS"
  if [ "$SPEC" != none ]; then
    # a graph spec states its own goal, so nothing is retyped and nothing drifts
    GOAL=$(sed -n 's/^GOAL:[[:space:]]*//p' "$SPEC" | head -n 1)
    SPEC_KIND=graph
  fi
  if [ "$SPEC" != none ] && [ -z "$GOAL" ]; then
    # any other file: its first h1 states the subject, and the filename says so when there is none
    SPEC_KIND=brief
    GOAL=$(sed -n 's/^#[[:space:]]\{1,\}//p' "$SPEC" | head -n 1)
  fi
  if [ "$SPEC_KIND" = brief ] && [ -z "$GOAL" ]; then
    GOAL=$(printf '%s' "$STEM" | tr '-' ' ')
  fi
  if [ -z "$GOAL" ]; then
    echo "fatal: /retardify:plan needs a goal or a path to read one from" >&2; exit 1; fi

  # the validator accepts letters digits and hyphens only, so all else collapses to a hyphen
  # 36 matches the graph cap, so a plan named here can still pair with a spec naming it there
  slugify() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]' \
      | sed -e 's/[^a-z0-9]/-/g' -e 's/--*/-/g' -e 's/^-//' -e 's/-$//' | cut -c1-36
  }
  SLUG=$(slugify "$GOAL")
  # a brief's filename is tighter than its opening heading, so it names the plan wherever it can
  if [ "$SPEC_KIND" = brief ] && [ -n "$(slugify "$STEM")" ]; then SLUG=$(slugify "$STEM"); fi
  SLUG=${SLUG%-}
  if [ -z "$SLUG" ]; then
    echo "fatal: the goal has no letters or digits to build a filename from" >&2; exit 1; fi

  mkdir -p "$ARTIFACTS"
  TARGET="$ARTIFACTS/$TODAY-operation-$SLUG.md"
  # a source already named like a plan hands its name over, which is the pairing --plan promises
  # any other name is derived instead, since an inherited one would fail the filename check
  if printf '%s' "$BASE" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}-operation-[A-Za-z0-9-]+\.md$'; then
    TARGET="$ARTIFACTS/$BASE"
  fi
  if [ -e "$TARGET" ]; then COLLISION=yes; else COLLISION=no; fi
  EXISTING=$(find "$ARTIFACTS" -maxdepth 1 -type f -name '*.md' | wc -l | tr -d ' ')

  echo "=== /retardify:plan telemetry ==="
  echo "goal: $GOAL"
  echo "spec: $SPEC"
  echo "spec_kind: $SPEC_KIND"
  echo "slug: $SLUG"
  echo "target: $TARGET"
  echo "collision: $COLLISION"
  echo "existing_plans: $EXISTING"
  echo "template: $TEMPLATE"
  echo "validator: $VALIDATOR"

  # an unchecked box in an older plan is unshipped work, which is where a blocker comes from
  echo "--- open plans (unchecked boxes) ---"
  while IFS= read -r plan; do
    [ -z "$plan" ] && continue
    OPEN=$(grep -c '^- \[ \]' "$plan" 2>/dev/null || true)
    OPEN=${OPEN:-0}
    if [ "$OPEN" -gt 0 ]; then echo "$plan: $OPEN open"; fi
  done < <(find "$ARTIFACTS" -maxdepth 1 -type f -name '*.md' | sort -r | head -10)

  if [ "$COLLISION" = yes ]; then
    echo "--- stop ---"
    echo "a plan already holds this slug; rename the goal or open the existing file"
  fi

  # a path resolves a goal, a filename and a target that nobody typed, so the run stops to show them
  # a wrong path would otherwise spend the whole write before anyone could read what it planned
  if [ "$SPEC" != none ] && [ "$CONFIRMED" -eq 0 ]; then
    echo "--- confirm ---"
    echo "confirm: required"
  fi
  echo "============================="
  exit 0
fi

# ==============
# PREFLIGHT
# ==============
# the shared scan sits beside this file, not beside the repo being scanned: resolve them before
# anything cds to a repo root, since BASH_SOURCE arrives relative and would follow that cd
SHARED=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../shared" 2>/dev/null && pwd || true)
if [ ! -f "$SHARED/secrets.sh" ]; then
  echo "fatal: no shared/secrets.sh reachable from this sidecar" >&2; exit 1; fi
# shellcheck source=../../shared/secrets.sh
. "$SHARED/secrets.sh"

# character counts, not byte counts: bash's ${#var} is multibyte-aware under a utf-8 locale, and
# every em dash in a plan is 3 bytes — a byte count would flag lines that are legally under the cap
UTF8_LOCALE=$(locale -a 2>/dev/null | grep -iE '^(C|en_US)\.(utf-?8)$' | head -n 1 || true)
if [ -n "$UTF8_LOCALE" ]; then export LC_ALL="$UTF8_LOCALE"; fi

MAX_WIDTH=100
STRICT=0
KEEP=0
TEMPLATE="plugins/retardify/skills/plan/SKILL.md"

# the template's own section order, which is the one thing every plan must agree on
EXPECTED_SECTIONS=$'Context\nGoal\nSolution\nRisks\nChecklist\nReadiness\nNotes'

# readiness runs blockers first, since that table gates starting the plan at all
EXPECTED_READINESS=$'Blockers\nAgents\nPermissions'

# the only actions a permissions row may propose; deny beats allow, so a denied path is
# narrowed at the deny rule rather than granted an allow that can never take effect
PERMISSION_ACTIONS=$'add to allow\nadd to ask\nnarrow deny\nremove from deny\nadd to deny\nadd to allowWrite\nadd to allowRead\nadd to denyRead\nadd to allowedDomains\nadd to deniedDomains\nadd to excludedCommands'

# the layer decides the rule shape, so the row check knows whether to expect `Tool(pattern)`
# or a bare path or host; a bash write needs a sandbox row even when a permission rule allows it
PERMISSION_LAYERS=$'permissions\nsandbox filesystem\nsandbox domain'

# managed is a sudo edit and a policy decision, so a plan proposes the four below and never it
PERMISSION_SCOPES=$'user\nproject\nlocal\ncli'

PLANS=()
for arg in "$@"; do
  case "$arg" in
    --strict) STRICT=1;;
    --keep) KEEP=1;;
    -*) echo "fatal: unknown flag $arg" >&2; exit 1;;
    *) PLANS+=("$arg");;
  esac
done

# no paths given: scan the whole artifact directory, anchored to the repo root so the default
# works from any subdirectory — same posture as the @git* sidecars
if [ ${#PLANS[@]} -eq 0 ]; then
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "fatal: not a git repository, and no paths given" >&2; exit 1; fi
  cd "$(git rev-parse --show-toplevel)"
  if [ ! -d .construct/retardify/plan ]; then echo "fatal: no .construct/retardify/plan/ to scan" >&2; exit 1; fi
  PLANS=(.construct/retardify/plan/*.md)
fi

# a directory argument expands to the plans inside it
EXPANDED=()
for path in "${PLANS[@]}"; do
  if [ -d "$path" ]; then
    for nested in "$path"/*.md; do [ -f "$nested" ] && EXPANDED+=("$nested"); done
  elif [ -f "$path" ]; then EXPANDED+=("$path")
  else echo "fatal: no such plan: $path" >&2; exit 1; fi
done
PLANS=("${EXPANDED[@]}")

# repo-local scratch: the sandbox denies writes outside cwd, and macos mktemp ignores TMPDIR
TMPROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)/tmp"
TMPTAG=$(basename "${BASH_SOURCE[0]}" .sh)
mkdir -p "$TMPROOT"

# findings collect as "SEV|file|line|category|detail" — line is its own field so the report can
# sort numerically; joining it to the path first sorts 121 above 31. the run fails on ERROR only
FINDINGS=$(mktemp "$TMPROOT/$TMPTAG-findings.XXXXXX")
SCRATCH=$(mktemp -d "$TMPROOT/$TMPTAG-scratch.XXXXXX")
# a failed run leaves scratch behind to read; --keep does the same after a clean one
cleanup() { st=$?; if [ "$KEEP" -eq 0 ] && [ "$st" -eq 0 ]; then rm -rf "$FINDINGS" "$SCRATCH"; fi; }
trap cleanup EXIT

err()  { printf 'ERROR|%s|%s|%s|%s\n' "$1" "$2" "$3" "$4" >> "$FINDINGS"; }
warn() { printf 'WARN|%s|%s|%s|%s\n' "$1" "$2" "$3" "$4" >> "$FINDINGS"; }

# emit "LINENO<TAB>TEXT" for every line inside a "## <name>" section, stopping at the next "## "
section() {
  awk -v want="## $2" '
    $0 == want { inside = 1; next }
    /^## / { inside = 0 }
    inside { print NR "\t" $0 }
  ' "$1"
}

# markdown counts cells between pipes, so mask the escaped ones first: a permission rule like
# `Bash(curl * | bash)` is a real entry in the settings files and would read as extra columns
table_cells() {
  printf '%s' "$1" | sed 's/\\|/~/g' | awk -F'|' '{ n = NF - 2; if (n < 0) n = 0; print n }'
}

# one cell of a table row, 1-indexed, trimmed; masking keeps an escaped pipe inside its own cell
row_cell() {
  printf '%s' "$1" | sed 's/\\|/~/g' \
    | awk -F'|' -v n="$2" '{ cell = $(n + 1); gsub(/^[ \t]+|[ \t]+$/, "", cell); print cell }'
}

# the 1-indexed position of a named column in a header row, empty when the table lacks it
# columns are looked up by name rather than position, since the order is the template's to change
col_index() {
  printf '%s' "$1" | sed 's/\\|/~/g' | awk -F'|' -v want="$2" '
    {
      for (i = 2; i < NF; i++) {
        cell = $i
        gsub(/^[ \t]+|[ \t]+$/, "", cell)
        if (tolower(cell) == want) { print i - 1; exit }
      }
    }'
}

# a count cell is a number, or an em dash standing in for zero; anything else is prose
count_cell() {
  case "$1" in
    ""|"—"|"–"|"-") printf '0';;
    *[!0-9]*) printf '';;
    *) printf '%s' "$1";;
  esac
}

# how many checkboxes a numbered stage holds; deferred work is unnumbered, so it counts for none
stage_items() {
  local file=$1 want=$2 lineno text stage current=0 count=0
  while IFS=$'\t' read -r lineno text; do
    case "$text" in
      "### "*)
        stage=$(printf '%s' "$text" | sed -n 's/^### \([0-9]\{1,\}\)\..*/\1/p')
        current=${stage:-0}
        continue;;
      "- [ ] "*|"- [x] "*)
        if [ "$current" = "$want" ]; then count=$((count + 1)); fi
        continue;;
    esac
  done < <(section "$file" Checklist)
  printf '%s' "$count"
}

# a plan closes with a numbered note opening on CLOSED, and a closed checklist is a record
# an abandoned item stays unticked forever, so tick state alone cannot say whether work is live
plan_closed() {
  grep -qE '^[0-9]{1,}\. CLOSED ' "$1"
}

# a stage's HUMAN labels, and how many of its items still read as live work; both from one walk
# a struck item is abandoned and a moved one records where it went, so neither is work to do
stage_humans() {
  local file=$1 want=$2 lineno text stage body current=0 skipped labels=0 live=0
  while IFS=$'\t' read -r lineno text; do
    case "$text" in
      "### "*)
        stage=$(printf '%s' "$text" | sed -n 's/^### \([0-9]\{1,\}\)\..*/\1/p')
        current=${stage:-0}
        continue;;
      "- [ ] "*|"- [x] "*) ;;
      *) continue;;
    esac
    if [ "$current" != "$want" ]; then continue; fi
    body=${text#*] }
    skipped=0
    # the label sits inside the tildes on a skipped item, so the row still sums after a skip
    case "$body" in '~~SKIPPED: '*) body=${body#'~~SKIPPED: '}; skipped=1;; esac
    case "$body" in "HUMAN: "*) labels=$((labels + 1));; esac
    case "$text" in "- [x] "*) continue;; esac
    if [ "$skipped" -eq 1 ]; then continue; fi
    case "$body" in MOVED*|SUPERSEDED*|DROPPED*|CLOSED*) continue;; esac
    live=$((live + 1))
  done < <(section "$file" Checklist)
  printf '%s\t%s' "$labels" "$live"
}

# ==============
# CHECKS
#   each takes a plan path and appends findings; to add one, write a function and list it below
# ==============

# "one file per plan, `.construct/retardify/plan/`, named `YYYY-MM-DD-operation-<title>.md`"
# caps are allowed in the title because `-DONE` is the closed-plan suffix
check_filename() {
  local file=$1 base dir
  base=$(basename "$file")
  dir=$(dirname "$file")
  if ! printf '%s' "$base" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}-operation-[A-Za-z0-9-]+\.md$'; then
    err "$file" 1 filename "expected YYYY-MM-DD-operation-<title>.md"
  fi
  case "$dir" in
    .construct/retardify/plan|./.construct/retardify/plan|*/.construct/retardify/plan) ;;
    *) warn "$file" 1 location "one plan per file, all of them in .construct/retardify/plan/";;
  esac
}


# "# AGENT PLAN: Operation [title]" then "one plain-english line: what this plan does"
check_header() {
  local file=$1 title summary blank
  title=$(sed -n '1p' "$file")
  summary=$(sed -n '2p' "$file")
  blank=$(sed -n '3p' "$file")
  case "$title" in
    "# AGENT PLAN: Operation"*) ;;
    "# AGENT PLAN:"*) warn "$file" 1 title "the template names every plan an Operation";;
    *) err "$file" 1 title "line 1 must read '# AGENT PLAN: Operation <title>'";;
  esac
  if [ -z "$summary" ] || [ "${summary:0:1}" = "#" ]; then
    err "$file" 2 summary "line 2 must be the one plain-english line: what this plan does"
  fi
  if [ -n "$blank" ]; then
    err "$file" 3 summary "line 3 must be blank; the summary is one line and never wraps"
  fi
}

# "sections run in this order: context, goal, solution, risks, checklist, readiness, notes"
check_sections() {
  local file=$1 actual
  actual=$(grep -E '^## ' "$file" | sed 's/^## //' || true)
  if [ "$actual" != "$EXPECTED_SECTIONS" ]; then
    err "$file" 1 section_order "got $(printf '%s' "$actual" | tr '\n' '>' | sed 's/>$//')"
  fi
}

# "`lines` carry a single clause, capped at 100 characters, and never wrap"
check_width() {
  local file=$1 lineno=0 line
  while IFS= read -r line; do
    lineno=$((lineno + 1))
    if [ ${#line} -gt "$MAX_WIDTH" ]; then
      err "$file" "$lineno" width "${#line} chars; the cap is $MAX_WIDTH"
    fi
  done < "$file"
}

# a stray fence swallows the rest of the plan when rendered, so it is never cosmetic
check_fences() {
  local file=$1 count
  count=$(grep -cE '^[[:space:]]*```' "$file" || true)
  if [ $((count % 2)) -ne 0 ]; then
    err "$file" 1 fences "$count fence markers; one is unclosed"
  fi
}

# the body carries one clause per line, so a bare continuation line means a bullet wrapped
# the template allows a single description line under the heading, before the bullets start
check_clauses() {
  local file=$1 name lineno text started fenced
  for name in Context Solution Risks; do
    started=0
    fenced=0
    while IFS=$'\t' read -r lineno text; do
      if [ -z "$text" ]; then continue; fi
      # the ALERT block closes the risks section, so its rows are fenced content rather than clauses
      case "$text" in
        '```'*) fenced=$((1 - fenced)); continue;;
      esac
      if [ "$fenced" -eq 1 ]; then continue; fi
      case "$text" in
        "- "*) started=1; continue;;
      esac
      if [ "$started" -eq 0 ]; then started=1; continue; fi
      err "$file" "$lineno" wrapped_clause "$name lines carry a single clause and never wrap"
    done < <(section "$file" "$name")
  done
}

# "a tree or diagram that makes the destination concrete" — and no change markers inside it,
# because a checkbox in the goal describes what changes rather than what things ARE
check_goal() {
  local file=$1 body lineno text
  body=$(section "$file" Goal | cut -f2-)
  case "$body" in
    *'```'*|*'|'*) ;;
    *) warn "$file" 1 goal_diagram "the goal needs a tree, diagram or table beneath its one line";;
  esac
  while IFS=$'\t' read -r lineno text; do
    case "$text" in
      *"- [ ]"*|*"- [x]"*) warn "$file" "$lineno" goal_markers "no change markers or stage numbers in the goal";;
    esac
  done < <(section "$file" Goal)
}

# "label each with a noun naming the actual risk" — the label is the leading backticked span
check_risks() {
  local file=$1 lineno text
  while IFS=$'\t' read -r lineno text; do
    case "$text" in "- "*) ;; *) continue;; esac
    printf '%s' "$text" | grep -qE '^- `[^`]+`' \
      || err "$file" "$lineno" risk_label 'risk needs a leading `noun` label, never a category'
  done < <(section "$file" Risks)
}

# stages are "### <n>. <name>" and hold "short directives, verb first, one line each"
# one orienting line under a stage header is fine; rationale between items belongs in a note
# "deferred work closes the checklist", so it is the one unnumbered heading allowed here
check_checklist() {
  local file=$1 lineno text stage previous=0 items=0 deferred=0
  while IFS=$'\t' read -r lineno text; do
    if [ -z "$text" ]; then continue; fi
    case "$text" in
      "### Deferred Work")
        items=0
        deferred=$lineno
        continue;;
      "### "*)
        items=0
        if [ "$deferred" -ne 0 ]; then
          warn "$file" "$lineno" stage_after_deferred "deferred work closes the checklist"
        fi
        stage=$(printf '%s' "$text" | sed -n 's/^### \([0-9]\{1,\}\)\..*/\1/p')
        if [ -z "$stage" ]; then
          err "$file" "$lineno" stage_header "stages are '### <n>. <name>'"
        else
          if [ "$stage" -ne $((previous + 1)) ]; then
            warn "$file" "$lineno" stage_order "stage $stage follows $previous; the numbering skips"
          fi
          previous=$stage
        fi
        continue;;
      "- [ ] "*|"- [x] "*) items=1; continue;;
      " "*) continue;;
      "**"*) continue;;
    esac
    if [ "$items" -eq 1 ]; then
      warn "$file" "$lineno" checklist_prose "no prose between items; point at a note instead"
    fi
  done < <(section "$file" Checklist)
}

# "abandoned items are wrapped in tildes, never deleted", so an open box is live work or a skip
# a closed plan is exempt, since its checklist froze at close under whatever rules it shipped with
check_skips() {
  local file=$1 lineno text body
  if plan_closed "$file"; then return; fi
  while IFS=$'\t' read -r lineno text; do
    case "$text" in
      "- [ ] "*|"- [x] "*) ;;
      *) continue;;
    esac
    body=${text#*] }
    check_skip_item "$file" "$lineno" "$text" "$body"
  done < <(section "$file" Checklist)
}

# one item, judged three ways; split out so the walk above stays a walk
check_skip_item() {
  local file=$1 lineno=$2 text=$3 body=$4
  # a tick says the work happened, which is the one thing a skip says it never did
  case "$text" in
    "- [x] "*)
      case "$body" in
        *SKIPPED*) err "$file" "$lineno" skip_ticked "a skipped item stays unticked";;
      esac
      return;;
  esac
  # struck through, so it has to name itself a skip rather than leave the reader guessing
  case "$body" in
    '~~'*)
      printf '%s' "$body" | grep -qE '^~~SKIPPED: .+~~$' \
        || err "$file" "$lineno" skip_shape 'a struck item reads "~~SKIPPED: <why>~~"'
      return;;
  esac
  # bare, so it reads as live work; a disposition word here is an abandonment nobody struck
  if printf '%s' "$body" | grep -qE '^(SKIPPED|MOVED|SUPERSEDED|DROPPED|ABANDONED)\b'; then
    err "$file" "$lineno" skip_tildes 'an abandoned item is wrapped in tildes, never left bare'
  fi
}

# "agents count every item in a stage as agentic, gated, or human-only, and the three sum"
# a row that does not sum is wrong, and its HUMAN labels say the human count a second time
check_agents_row() {
  local file=$1 lineno=$2 text=$3 header=$4 stage agentic gated human total items humans labels live
  stage=$(row_cell "$text" "$(col_index "$header" stage)" | sed -n 's/^\([0-9]\{1,\}\)\..*/\1/p')
  if [ -z "$stage" ]; then
    err "$file" "$lineno" agents_row "each row leads with a numbered stage from the checklist"
    return
  fi
  agentic=$(count_cell "$(row_cell "$text" "$(col_index "$header" agentic)")")
  gated=$(count_cell "$(row_cell "$text" "$(col_index "$header" gated)")")
  human=$(count_cell "$(row_cell "$text" "$(col_index "$header" human-only)")")
  if [ -z "$agentic" ] || [ -z "$gated" ] || [ -z "$human" ]; then
    err "$file" "$lineno" agents_counts "a count is a number or an em dash, never prose"
    return
  fi
  total=$((agentic + gated + human))
  items=$(stage_items "$file" "$stage")
  if [ "$items" -eq 0 ]; then
    err "$file" "$lineno" agents_stage "stage $stage has no checklist items to classify"
  elif [ "$total" -ne "$items" ]; then
    err "$file" "$lineno" agents_sum "counts sum to $total; stage $stage holds $items items"
  fi
  # a closed plan, or a stage holding no live work, is a record; its labels go ungraded
  humans=$(stage_humans "$file" "$stage")
  labels=${humans%%$'\t'*}
  live=${humans##*$'\t'}
  if [ "$live" -gt 0 ] && [ "$labels" -ne "$human" ] && ! plan_closed "$file"; then
    err "$file" "$lineno" human_labels "stage $stage labels $labels HUMAN; the row counts $human"
  fi
}

# "every permission rule is quoted exactly from a settings file", so the cell carries a real
# rule string; the action vocabulary is closed because deny beats allow
check_permissions_row() {
  local file=$1 lineno=$2 text=$3 header=$4 rule layer scope action
  rule=$(row_cell "$text" "$(col_index "$header" rule)")
  layer=$(row_cell "$text" "$(col_index "$header" layer)")
  scope=$(row_cell "$text" "$(col_index "$header" scope)")
  action=$(row_cell "$text" "$(col_index "$header" suggestion)")

  # a permissions row quotes `Tool(pattern)`, while a sandbox row quotes a bare path or host,
  # so the shape check follows the layer rather than assuming every row is a permission rule
  if [ "$layer" = "permissions" ]; then
    printf '%s' "$rule" | grep -qE '`[A-Za-z]+\([^`]*\)`' \
      || err "$file" "$lineno" permission_rule 'quote the rule itself, as `Tool(pattern)`'
  else
    printf '%s' "$rule" | grep -qE '`[^`]+`' \
      || err "$file" "$lineno" permission_rule 'quote the path or host in backticks'
  fi

  if ! printf '%s' "$PERMISSION_LAYERS" | grep -qxF "$layer"; then
    err "$file" "$lineno" permission_layer "layer is one of: $(printf '%s' "$PERMISSION_LAYERS" | tr '\n' '/')"
  fi
  if ! printf '%s' "$PERMISSION_SCOPES" | grep -qxF "$scope"; then
    err "$file" "$lineno" permission_scope "scope is one of: $(printf '%s' "$PERMISSION_SCOPES" | tr '\n' '/')"
  fi
  if ! printf '%s' "$PERMISSION_ACTIONS" | grep -qxF "$action"; then
    err "$file" "$lineno" permission_action "action is one of: $(printf '%s' "$PERMISSION_ACTIONS" | tr '\n' '/')"
  fi
}

# a table the row checks cannot read is reported once, against its header, rather than once per
# row: the missing column is the single cause, and repeating it per row buries everything else
check_table_header() {
  local file=$1 lineno=$2 header=$3 sub=$4 name missing=""
  case "$sub" in
    Agents) set -- stage agentic gated human-only;;
    Permissions) set -- rule layer scope suggestion;;
    *) return 0;;
  esac
  for name in "$@"; do
    if [ -z "$(col_index "$header" "$name")" ]; then missing="$missing $name"; fi
  done
  if [ -n "$missing" ]; then
    err "$file" "$lineno" table_header "$sub is missing a column:$missing"
    return 1
  fi
  return 0
}

# "readiness states feasibility only" — three tables in a fixed order, each shape-checked against
# its own header row, since a row short one cell renders as a silently truncated table
check_readiness() {
  local file=$1 lineno text actual sub="" header=0 cells hdr=""
  # a plan missing the section entirely is already reported by check_sections; saying it twice
  # buries the finding that matters under a second one naming the same cause
  if [ -z "$(section "$file" Readiness)" ]; then return; fi
  actual=$(section "$file" Readiness | cut -f2- | grep -E '^### ' | sed 's/^### //' || true)
  if [ "$actual" != "$EXPECTED_READINESS" ]; then
    err "$file" 1 readiness_order "got $(printf '%s' "$actual" | tr '\n' '>' | sed 's/>$//')"
  fi

  while IFS=$'\t' read -r lineno text; do
    case "$text" in
      "### "*) sub=$(printf '%s' "$text" | sed 's/^### //'); header=0; hdr=""; continue;;
      "|"*) ;;
      *) continue;;
    esac
    cells=$(table_cells "$text")
    if [ "$header" -eq 0 ]; then
      header=$cells
      hdr=$text
      check_table_header "$file" "$lineno" "$hdr" "$sub" || hdr=""
      continue
    fi
    if [ "$cells" -ne "$header" ]; then
      err "$file" "$lineno" table_shape "$cells columns where the header has $header"
      continue
    fi
    case "$text" in *---*) continue;; esac
    if [ -z "$hdr" ]; then continue; fi
    case "$sub" in
      Agents) check_agents_row "$file" "$lineno" "$text" "$hdr";;
      Permissions) check_permissions_row "$file" "$lineno" "$text" "$hdr";;
    esac
  done < <(section "$file" Readiness)
}

# "`notes` are numbered so every `(see #x)` resolves" and "a note nothing points at is either
# dead weight or a missing `(see #x)` somewhere"
check_notes() {
  local file=$1 lineno text number expected=1 missing orphan hit
  : > "$SCRATCH/defined"
  while IFS=$'\t' read -r lineno text; do
    number=$(printf '%s' "$text" | sed -n 's/^\([0-9]\{1,\}\)\. .*/\1/p')
    if [ -z "$number" ]; then continue; fi
    printf '%s\n' "$number" >> "$SCRATCH/defined"
    if [ "$number" -ne "$expected" ]; then
      err "$file" "$lineno" note_numbering "note $number where $expected was expected; renumbering breaks every reference"
    fi
    expected=$((number + 1))
  done < <(section "$file" Notes)
  sort -un "$SCRATCH/defined" -o "$SCRATCH/defined"

  # matches "(see #4)" and comma-chained forms like "(see #2, #11, #12)", while a leading
  # "(PR #79, see #22)" contributes only the 22 — pr numbers are not note numbers
  grep -oE 'see #[0-9]+([[:space:]]*,[[:space:]]*#[0-9]+)*' "$file" 2>/dev/null \
    | grep -oE '[0-9]+' | sort -un > "$SCRATCH/refs" || true
  if [ ! -s "$SCRATCH/refs" ]; then : > "$SCRATCH/refs"; fi

  while IFS= read -r missing; do
    if [ -z "$missing" ]; then continue; fi
    hit=$(grep -nE "see #$missing\\b" "$file" | head -n 1 | cut -d: -f1 || true)
    err "$file" "${hit:-1}" dangling_note "(see #$missing) resolves to nothing"
  done < <(comm -23 "$SCRATCH/refs" "$SCRATCH/defined")

  while IFS= read -r orphan; do
    if [ -z "$orphan" ]; then continue; fi
    hit=$(grep -nE "^$orphan\\. " "$file" | head -n 1 | cut -d: -f1 || true)
    warn "$file" "${hit:-1}" orphan_note "note $orphan: dead weight, or a missing (see #$orphan)"
  done < <(comm -13 "$SCRATCH/refs" "$SCRATCH/defined")
}


# an unanswered question is the one thing that can invalidate every stage below it, so it rides in
# a fence directly above the checklist rather than in a note the reader reaches after the work
check_alert() {
  local file=$1 open lineno text expected=1 asked=0
  open=$(grep -nE '^ALERT: ' "$file" | head -n 1 || true)
  if [ -z "$open" ]; then return 0; fi
  lineno=${open%%:*}
  if [ -z "$(sed -n "$((lineno - 1))p" "$file" | grep -E '^```')" ]; then
    err "$file" "$lineno" alert_unfenced 'the ALERT block opens on a code fence, or it reads as prose'
  fi
  while IFS= read -r text; do
    case "$text" in '```'*) break;; esac
    if [ -z "$text" ]; then continue; fi
    asked=$((asked + 1))
    if [ "$text" != "$(printf '%s' "$text" | sed -n "s/^$expected\\. .*/&/p")" ]; then
      err "$file" "$((lineno + asked))" alert_numbering "row $asked must open '$expected. '"
    fi
    expected=$((expected + 1))
  done < <(tail -n "+$((lineno + 1))" "$file")
  if [ "$asked" -eq 0 ]; then
    err "$file" "$lineno" alert_empty "an ALERT with no questions is a plan claiming to be blocked"
  fi
}

# --- run list (add new checks here) ---
for plan in "${PLANS[@]}"; do
  check_filename "$plan"
  check_header   "$plan"
  check_sections "$plan"
  check_width    "$plan"
  check_fences   "$plan"
  check_clauses  "$plan"
  check_goal     "$plan"
  check_risks    "$plan"
  check_alert    "$plan"
  check_checklist "$plan"
  check_skips    "$plan"
  check_readiness "$plan"
  check_notes    "$plan"
  scan_secrets   "$plan"
done

# ==============
# TELEMETRY
# ==============
ERRORS=$(grep -c '^ERROR|' "$FINDINGS" || true)
WARNINGS=$(grep -c '^WARN|' "$FINDINGS" || true)
SECRETS=$(grep -c '|secret|' "$FINDINGS" || true)

cat <<EOF

=== plan.sh sidecar ===
template: $TEMPLATE
scanned: ${#PLANS[@]} plan(s)
width_cap: $MAX_WIDTH chars
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
- written before complex or architectural work, not after it
- maximally clear, concise, action-oriented; plain english over jargon, facts over metaphor
- body sections state conclusions only; the reasoning lives in the numbered notes
- solution lines are decisions; a line that could be pasted into the checklist belongs there
- risks sort by blast radius and irreversibility, never by likelihood
- stages run in sequence and each ships as its own pr
- readiness states feasibility only; a row proposing new work belongs in the checklist
- every permission rule is quoted from a settings file, or the row says it is a proposal
- a bash step writing outside the working directory has a sandbox row, not only a permission one
- blockers are unrelated work found in other open plans, not work this plan creates
- every list is ordered deliberately; if the order is not obvious, a note says why
- a claim with a number in it is verified before it lands, or it does not land
- notes are self-contained, since readers jump in from one line and jump straight back
- a key that reached a commit is already leaked; rotate it before rewriting anything
========================
EOF

if [ "$ERRORS" -gt 0 ]; then exit 1; fi
if [ "$STRICT" -eq 1 ] && [ "$WARNINGS" -gt 0 ]; then exit 1; fi
exit 0

#!/bin/bash
# ===========================================
# @file doc-plans.sh - plan validator sidecar
# ===========================================
# @description
# PAIR
# - sidecar for `doc-plans` — asserts a plan matches the shape its SKILL.md documents
# - the doc carries seven sections and three tables; this file carries what a script can judge
# ARTIFACT
# - `docs/plans/YYYY-MM-DD-operation-<title>.md`, one file per plan
# - written before complex or architectural work, and closed out in `notes` rather than a summary
# - sections run in order: context, goal, solution, risks, checklist, readiness, notes
# - `checklist` holds the stages, each numbered, run in sequence, and each shipping as its own pr
# - `readiness` holds the blockers, agents and permissions tables, which is where a plan gets gated
# - `notes` are numbered so every `(see #x)` resolves, and are the only place verbosity belongs
# RUN
# - defaults to every file in `docs/plans/`; pass files or a directory to scope it
# - `--strict` promotes warnings to errors, `--keep` preserves scratch; exits 1 on any error
# - ERROR breaks a rule the doc states outright; WARN names a smell the doc tolerates
# @see AGENTS.md, AGENTS/skills/doc-plans/SKILL.md, AGENTS/skills/doc-graphs/SKILL.md, AGENTS/skills/doc-logs/SKILL.md, docs/plans/, AGENTS/settings/secrets.sh

set -euo pipefail

# ==============
# PREFLIGHT
# ==============
# the shared scan sits beside this file, not beside the repo being scanned: resolve them before
# anything cds to a repo root, since BASH_SOURCE arrives relative and would follow that cd
SHARED=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../settings" 2>/dev/null && pwd || true)
if [ ! -f "$SHARED/secrets.sh" ]; then
  echo "fatal: no AGENTS/settings/secrets.sh beside this sidecar" >&2; exit 1; fi
# shellcheck source=../../settings/secrets.sh
. "$SHARED/secrets.sh"

# character counts, not byte counts: bash's ${#var} is multibyte-aware under a utf-8 locale, and
# every em dash in a plan is 3 bytes — a byte count would flag lines that are legally under the cap
UTF8_LOCALE=$(locale -a 2>/dev/null | grep -iE '^(C|en_US)\.(utf-?8)$' | head -n 1 || true)
if [ -n "$UTF8_LOCALE" ]; then export LC_ALL="$UTF8_LOCALE"; fi

MAX_WIDTH=100
STRICT=0
KEEP=0
TEMPLATE="AGENTS/skills/doc-plans/SKILL.md"

# the template's own section order, which is the one thing every plan must agree on
EXPECTED_SECTIONS=$'Context\nGoal\nSolution\nRisks\nChecklist\nReadiness\nNotes'

# readiness runs blockers first, since that table gates starting the plan at all
EXPECTED_READINESS=$'Blockers\nAgents\nPermissions'

# the only actions a permissions row may propose; deny beats allow, so a denied path is
# narrowed at the deny rule rather than granted an allow that can never take effect
PERMISSION_ACTIONS=$'add to allow\nnarrow deny\nremove from deny\nadd to deny\nadd to allowWrite\nadd to allowRead\nadd to denyRead\nadd to allowedDomains\nadd to deniedDomains\nadd to excludedCommands'

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
    -h|--help) sed -n '2,12p' "$0"; exit 0;;
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
  if [ ! -d docs/plans ]; then echo "fatal: no docs/plans/ to scan" >&2; exit 1; fi
  PLANS=(docs/plans/*.md)
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

# ==============
# CHECKS
#   each takes a plan path and appends findings; to add one, write a function and list it below
# ==============

# "one file per plan, `docs/plans/`, named `YYYY-MM-DD-operation-<title>.md`"
# caps are allowed in the title because `-DONE` is the closed-plan suffix
check_filename() {
  local file=$1 base dir
  base=$(basename "$file")
  dir=$(dirname "$file")
  if ! printf '%s' "$base" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}-operation-[A-Za-z0-9-]+\.md$'; then
    err "$file" 1 filename "expected YYYY-MM-DD-operation-<title>.md"
  fi
  case "$dir" in
    docs/plans|./docs/plans|*/docs/plans) ;;
    *) warn "$file" 1 location "one plan per file, all of them in docs/plans/";;
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
  local file=$1 name lineno text started
  for name in Context Solution Risks; do
    started=0
    while IFS=$'\t' read -r lineno text; do
      if [ -z "$text" ]; then continue; fi
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

# "agents count every item in a stage as agentic, gated, or human-only, and the three sum"
# a row that does not sum is provably wrong, which is the whole reason the counts are counts
check_agents_row() {
  local file=$1 lineno=$2 text=$3 header=$4 stage agentic gated human total items
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
  check_checklist "$plan"
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

=== plans.sh sidecar ===
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

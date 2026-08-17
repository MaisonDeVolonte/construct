#!/bin/bash
# ==================================================
# @file output.sh - output style conformance linter
# ==================================================
# @description
# PAIR
# - sidecar for `/retardify:output` — grades one reply against the Output Style spec
# - findings carry the spec's own addresses, so a report reads B1, C2, V2 or F1 rather than prose
# - a line finding also quotes its line, since the reader of a report no longer holds the reply
# - B3, F2 to F4, F6, F7, C1, C4 to C7 and every Grounding row stay the agent's job
# - reads a file holding the reply text, or stdin when the path is `-`
# - a plain run with no path grades this session's own last reply, read from its transcript
# - that means the LAST ASSISTANT TEXT, since a plain run always arrives with a user turn on top
# - the stop action reads the last MESSAGE instead, so it can skip a turn still being written
# - the two extractions stay separate for that reason; collapsing them would break the mid-turn skip
# - the stop action `retardify-output.sh` calls it the same way a user does
# NUMBERS
# - the width and the ceiling are read from the style copy beside this skill, never restated
# - the hardcoded constants only hold when that copy is absent, so the spec stays the one source
# TIERS
# - HARD findings block a turn: B1 markup, C2 width, C8 ceiling, F1 closer, and B2 gone to prose
# - SOFT findings only ride along with a hard one, since one stray prose line is a nit
# - B2 stays soft until it passes WRAP_TOLERANCE, which is the line between a nit and paragraphs
# ACTION
# - V2, F5 and F1 grade what a reply hands back: a coordinate, a command, and a closing action
# - they are whole-reply counts rather than per-line tests, which is what keeps them quiet
# - V2 fires when a reply names files and carries no `path:line` beside any of them
# - F5 fires when a reply tells the user to run something and carries nothing pasteable
# - F1 is HARD, since a reply that never lands on an action costs the user another turn to ask
# - a reply under SIGNAL_FLOOR counted lines is exempt from F1, since C4 caps a yes/no at one line
# - the counts accumulate before the table and quote exemptions, since findings tables carry them
# - skipping those rows would read a coordinate-rich table as a reply holding none
# EXEMPT
# - C10 names them: code, terminal output, quoted content and tables, plus blank lines from C3
# - a fence closes only on a delimiter at least as long as the one that opened it
# - that is what stops a nested block from ending the wider fence around it early
# - a fence, a table or a quote may sit indented under a list item, so leading space is shed first
# - a bare fence is left alone, since quoting a draft has no language to name
# COST
# - every test is a bash builtin; a fork per line would put 3 subprocesses per line in a stop hook
# @see plugins/retardify/skills/output/SKILL.md, plugins/retardify/output-styles/operator.md, plugins/operator/hooks/stop/retardify-output.sh

set -euo pipefail

# the doc is read only after this has already run, so help is refused here or not at all; the doc's
# own '## Help' section owns the output, which is why this prints a marker rather than a usage text
case " $* " in *" --help "*|*" -h "*) echo "help: requested"; exit 0;; esac

# the style copy beside this skill owns the numbers; the constants only hold when it is absent
STYLE_COPY="$(dirname "${BASH_SOURCE[0]}")/../../output-styles/operator.md"
MAX_WIDTH=$(sed -n 's/.*\[C2\] lines:.*[^0-9]\([0-9]\{1,\}\) characters.*/\1/p' "$STYLE_COPY" 2>/dev/null | head -n 1)
MAX_WIDTH=${MAX_WIDTH:-100}
MAX_LINES=$(sed -n 's/.*\[C8\] reply ceiling:[^0-9]*\([0-9]\{1,\}\).*/\1/p' "$STYLE_COPY" 2>/dev/null | head -n 1)
MAX_LINES=${MAX_LINES:-30}
# a stray prose line is a nit; four of them is a paragraph, which is the failure worth blocking
WRAP_TOLERANCE=3

SOURCE=${1:-}

# a plain run means "grade what you just said", so the reply is fetched rather than demanded
last_reply() {
  local transcript projects="$HOME/.claude/projects"
  [ -n "${CLAUDE_CODE_SESSION_ID:-}" ] || return 0
  [ -d "$projects" ] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  transcript=$(find "$projects" -maxdepth 2 -name "$CLAUDE_CODE_SESSION_ID.jsonl" -type f \
    2>/dev/null | head -1 || true)
  [ -n "$transcript" ] || return 0
  jq -rs '[ .[]
    | select(.isSidechain != true)
    | select(.type == "assistant")
    | [ .message.content[]? | select(.type == "text") | .text ] | join("\n")
    | select(length > 0) ] | last // ""' "$transcript" 2>/dev/null || true
}

# an unreadable path grades as an empty reply, since strict mode would otherwise exit 1 here and
# a bare exit 1 reads as hard findings to the stop action that calls this
if [ -n "$SOURCE" ]; then
  BODY=$(if [ "$SOURCE" = "-" ]; then cat; else cat "$SOURCE" 2>/dev/null || true; fi)
else
  BODY=$(last_reply)
  # no session and no path is the one case with nothing to grade, so it still refuses rather than
  # waiting on a stdin nobody is going to write
  if [ -z "$BODY" ]; then echo "usage: output.sh <file>|- (no reply reachable)" >&2; exit 2; fi
fi
if [ -z "$BODY" ]; then exit 0; fi

HARD=0
SOFT=0
FINDINGS=''
WRAPPED=0

# a one-line yes/no answer owes no closing action, since C4 caps that reply at the one line
SIGNAL_FLOOR=5

# what the reply hands back, counted across the whole of it rather than judged line by line
NAMED_FILE=0
NAMED_COORD=0
NAMED_ACTION=0
HAS_FENCE=0
HAS_TICK=0
LAST_TEXT=''
LAST_KIND=''

# a file token is judged by its extension, since no test tells a bare word from a path
FILE_RE='[A-Za-z0-9_.-]+\.(ts|tsx|js|jsx|mjs|cjs|sh|bash|zsh|py|rb|go|rs|json|md|yml|yaml'
FILE_RE="$FILE_RE|toml|css|scss|html|sql|java|php|vue|svelte)"
COORD_RE="$FILE_RE:[0-9]"

# the verbs that hand work back to the user; each one owes a command the user can paste
ACTION_RE='(^|[[:space:]])([Rr]un|[Pp]aste|[Ee]xecute|[Rr]e-run|[Rr]erun|[Ii]nvoke)[[:space:]]'

# the offending line itself, carried so a finding quotes the text rather than only addressing it
# the reader of a finding no longer holds the reply, so an address alone cannot be repaired
CITE=''
CITE_CAP=120

# a finding names the rule and the line, then quotes the text; HARD ones decide the exit code
cite_onto() {
  if [ "$1" != 0 ] && [ -n "$CITE" ]; then FINDINGS="$FINDINGS | ${CITE:0:$CITE_CAP}"; fi
}
hard() {
  HARD=$((HARD + 1))
  FINDINGS="$FINDINGS
HARD $1:$2 $3"
  cite_onto "$2"
}
soft() {
  SOFT=$((SOFT + 1))
  FINDINGS="$FINDINGS
SOFT $1:$2 $3"
  cite_onto "$2"
}

# emoji as bytes rather than characters: the spec allows … and — which are non-ascii too, so a
# blanket non-ascii test would fire on the punctuation the style uses in its own examples
EMOJI_HI=$'\xf0\x9f'
EMOJI_MISC=$'\xe2\x9c'
EMOJI_MARK=$'\xe2\x9d'
EMOJI_WARN=$'\xe2\x9a'

FENCE_LEN=0
COUNTED=0
LINE=0
while IFS= read -r raw; do
  LINE=$((LINE + 1))
  CITE=$raw

  # an indented fence, table or quote is still one; shed the indent before deciding what it is
  text=${raw#"${raw%%[![:space:]]*}"}

  # the delimiter's own length decides the fence: a wider one opens a block a narrower cannot close
  if [[ $text == '```'* ]]; then
    ticks=${text%%[!\`]*}
    HAS_FENCE=1
    LAST_KIND=fence
    if [ "$FENCE_LEN" -eq 0 ]; then
      FENCE_LEN=${#ticks}
      case "${text#"$ticks"}" in
        text|plaintext|txt)
          hard B1 "$LINE" "fenced plaintext; name a language or use a list";;
      esac
      continue
    fi
    if [ "${#ticks}" -ge "$FENCE_LEN" ] && [ -z "${text#"$ticks"}" ]; then FENCE_LEN=0; fi
    continue
  fi
  if [ "$FENCE_LEN" -ne 0 ]; then
    if [ -n "$text" ]; then LAST_KIND=fence; fi
    continue
  fi

  if [ -z "$text" ]; then continue; fi
  COUNTED=$((COUNTED + 1))
  LAST_KIND=text
  LAST_TEXT=$text

  # counted before the table and quote exemptions below, since a findings table carries coordinates
  case "$text" in *'`'*) HAS_TICK=1;; esac
  if [[ $text =~ $FILE_RE ]]; then
    NAMED_FILE=$((NAMED_FILE + 1))
    if [[ $text =~ $COORD_RE ]]; then NAMED_COORD=$((NAMED_COORD + 1)); fi
  fi
  if [[ $text =~ $ACTION_RE ]]; then NAMED_ACTION=$((NAMED_ACTION + 1)); fi

  case "$text" in
    *"$EMOJI_HI"*|*"$EMOJI_MISC"*|*"$EMOJI_MARK"*|*"$EMOJI_WARN"*)
      hard B1 "$LINE" "emoji; B1 allows a list, a table, a fence or a backtick and nothing else";;
  esac
  if [[ $text =~ \*\*[^*]+\*\* || $text =~ __[^_]+__ ]]; then
    hard B1 "$LINE" "bold or italic; a LABEL: carries the emphasis instead"
  fi

  # C10 exempts a table row and quoted content, so neither earns a width or a shape finding
  case "$text" in
    '|'*|'>'*) continue;;
  esac

  if [ ${#raw} -gt "$MAX_WIDTH" ]; then
    hard C2 "$LINE" "${#raw} chars against a $MAX_WIDTH cap; cut it, do not wrap it"
  fi

# b6's shapes: an epigram is matchable where "plainly spoken" is not, so name the forms
if [[ $text =~ (is|are)\ not\ .+,\ (it|that|they)\ (is|are) ]] \
|| [[ $text =~ [a-z]\ beats\ [a-z] ]] \
|| [[ $text =~ (^|[[:space:]])[Nn]o\ [a-z]+\ without\ [a-z] ]] \
|| [[ $text =~ ,\ never\ [a-z]+([[:space:]][a-z]+)?$ ]] \
|| [[ $text =~ ,\ not\ (a|an|the|its|their)?[[:space:]]?[a-z]+([[:space:]][a-z]+)?$ ]]; then
soft B6 "$LINE" "epigram shape; name what it does, in the order it does it"
fi

  # b2's own definition: anything that is none of the allowed shapes is a wrapped prose line
  if [[ ! $text =~ ^([-*+]|[0-9]+\.)[[:space:]] && ! $text =~ ^#{1,6}[[:space:]] \
     && ! $text =~ ^[A-Z][A-Z0-9\ /_-]*: ]]; then
    WRAPPED=$((WRAPPED + 1))
    soft B2 "$LINE" "prose line; every line is a LABEL:, a list item, a table row, or fenced"
  fi
done <<< "$BODY"

# the findings below address the whole reply, so there is no single line left to quote
CITE=''

if [ "$FENCE_LEN" -ne 0 ]; then
  soft B1 0 "a fence opened and never closed; everything after it went ungraded"
fi

if [ "$COUNTED" -gt "$MAX_LINES" ]; then
  hard C8 0 "$COUNTED lines against a $MAX_LINES ceiling; cut, log the rest, cite the log"
fi

# soft findings never block alone, but a reply that has gone fully prose is not a nit any more
if [ "$WRAPPED" -gt "$WRAP_TOLERANCE" ]; then
  hard B2 0 "$WRAPPED prose lines against a tolerance of $WRAP_TOLERANCE; the reply is paragraphs"
fi

# V2 wants the coordinate rather than the file name, so a reply naming neither owes nothing here
if [ "$NAMED_FILE" -gt 0 ] && [ "$NAMED_COORD" -eq 0 ]; then
  soft V2 0 "$NAMED_FILE file names and no path:line; give the line beside at least one of them"
fi

# F5 puts a command in a fence, so an action handed back with nothing pasteable is the gap
if [ "$NAMED_ACTION" -gt 0 ] && [ "$HAS_FENCE" -eq 0 ] && [ "$HAS_TICK" -eq 0 ]; then
  soft F5 0 "$NAMED_ACTION lines telling the user to act, and nothing fenced or ticked to run"
fi

# F1 orders a reply as answer then evidence then actions; the last line is where actions land
# a fenced block closing the reply already IS the action, which is why it satisfies this
if [ "$COUNTED" -ge "$SIGNAL_FLOOR" ] && [ "$LAST_KIND" != fence ] \
   && [[ ! $LAST_TEXT =~ ^SIGNAL: ]]; then
  hard F1 0 "the reply never lands on an action; close on a SIGNAL: line or a pasteable block"
fi

if [ "$HARD" -eq 0 ] && [ "$SOFT" -eq 0 ]; then exit 0; fi

printf 'hard: %s\nsoft: %s%s\n' "$HARD" "$SOFT" "$FINDINGS"
if [ "$HARD" -gt 0 ]; then exit 1; fi
exit 0

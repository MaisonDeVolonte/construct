#!/bin/bash
# ==================================================
# @file output.sh - output style conformance linter
# ==================================================
# @description
# PAIR
# - sidecar for `/retardify:output` — grades one reply against the Output Style spec
# - findings carry the spec's own addresses, so a report reads B1, B2, C2 or C8 rather than prose
# - B3, F1 to F7, C1, C4 to C7 and every Grounding row stay the agent's job; no grep can judge them
# - reads a file holding the reply text, or stdin when the path is `-`
# - the stop action `retardify-output.sh` calls it the same way a user does
# NUMBERS
# - the width and the ceiling are read from the style copy beside this skill, never restated
# - the hardcoded constants only hold when that copy is absent, so the spec stays the one source
# TIERS
# - HARD findings block a turn: B1 markup, C2 width, C8 ceiling, and B2 once prose mode has won
# - SOFT findings only ride along with a hard one, since one stray prose line is a nit
# - B2 stays soft until it passes WRAP_TOLERANCE, which is the line between a nit and paragraphs
# EXEMPT
# - C10 names them: code, terminal output, quoted content and tables, plus blank lines from C3
# - a fence closes only on a delimiter at least as long as the one that opened it
# - that is what stops a nested block from ending the wider fence around it early
# - a fence, a table or a quote may sit indented under a list item, so leading space is shed first
# - a bare fence is left alone, since quoting a draft has no language to name
# COST
# - every test is a bash builtin; a fork per line would put 3 subprocesses per line in a stop hook
# @see plugins/retardify/skills/output/SKILL.md, plugins/retardify/output-styles/operator.md, plugins/operator/hooks/stop/retardify-output.sh

set -uo pipefail

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
if [ -z "$SOURCE" ]; then echo "usage: output.sh <file>|-" >&2; exit 2; fi

BODY=$(if [ "$SOURCE" = "-" ]; then cat; else cat "$SOURCE" 2>/dev/null; fi)
if [ -z "$BODY" ]; then exit 0; fi

HARD=0
SOFT=0
FINDINGS=''
WRAPPED=0

# a finding names the rule, the line, and what a fix looks like; HARD ones decide the exit code
hard() { HARD=$((HARD + 1)); FINDINGS="$FINDINGS
HARD $1:$2 $3"; }
soft() { SOFT=$((SOFT + 1)); FINDINGS="$FINDINGS
SOFT $1:$2 $3"; }

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

  # an indented fence, table or quote is still one; shed the indent before deciding what it is
  text=${raw#"${raw%%[![:space:]]*}"}

  # the delimiter's own length decides the fence: a wider one opens a block a narrower cannot close
  if [[ $text == '```'* ]]; then
    ticks=${text%%[!\`]*}
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
  if [ "$FENCE_LEN" -ne 0 ]; then continue; fi

  if [ -z "$text" ]; then continue; fi
  COUNTED=$((COUNTED + 1))

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

if [ "$HARD" -eq 0 ] && [ "$SOFT" -eq 0 ]; then exit 0; fi

printf 'hard: %s\nsoft: %s%s\n' "$HARD" "$SOFT" "$FINDINGS"
if [ "$HARD" -gt 0 ]; then exit 1; fi
exit 0

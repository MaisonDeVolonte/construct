---
name: output
model: opus
effort: high
license: MIT
compatibility: requires bash, git
description: output style linter run by the stop hook or via <path> argument
argument-hint: "[--help] <path>|-"
disable-model-invocation: true
metadata:
  kind: trigger
---
**every reply is linted:** against the output style rules to keep conversations consistent
- used by the `retardify-output.sh` `stop` hook automatically but can be used manually for debugging
- grades the mechanically checkable rules like markup, constraints, shapes, etc
- blocks on HARD findings and quotes the offending line so the fix is mechanical

# Instructions

## Telemetry
```!
if [ -n "$ARGUMENTS" ];
then "${CLAUDE_PLUGIN_ROOT}"/skills/output/output.sh $ARGUMENTS; echo "sidecar exit: $?"
else echo "no path given, so nothing ran; pass a reply file, or - to grade stdin"; fi
```
- `help: requested` → the run was refused before it started; `## Help` below is the whole turn
- this already ran; never re-issue it, and never a bare `output.sh`, which waits on stdin forever
- `fail (sidecar exit > 0)` → HARD findings: report them, fix the reply's shape, then regrade
- `success (sidecar exit = 0)` → clean or SOFT-only; note any SOFT findings and move on

## Findings
> every finding reads `TIER RULE:LINE detail`, and the rule is an address into the style spec

| rule | what it caught |
|---|---|
| `B1` | markup outside a list, table, fence or backtick: bold, italics, emoji, fenced plaintext |
| `B2` | a prose line, or past the tolerance, a reply that has gone fully paragraphs |
| `B6` | a banned sentence shape standing in for a plain statement |
| `C2` | a line wider than the spec's character cap |
| `C8` | a reply taller than the spec's line ceiling |
| `V2` | file names carrying no `path:line` coordinate anywhere in the reply |
| `F5` | an action handed to the user with nothing fenced or ticked to run |
| `F1` | a reply that never lands on an action, so the user has to ask for one |

- line 0 names a whole-reply finding: the ceiling, the prose tolerance, or one of the action rules
- `V2` and `F5` are SOFT, so they surface only when a HARD finding is already blocking
- `F1` is HARD, and a reply shorter than `SIGNAL_FLOOR` lines is exempt from it
- a reply satisfies `F1` with a final `SIGNAL:` line, or by closing on a fenced block
- the width and ceiling numbers come from `output-styles/operator.md`, read at run time

## Verify
- RUN `plugins/retardify/skills/output/output.sh <path>` on a saved reply, or pipe one to `-`
- FIX every HARD finding, since each one blocks a stop-hook turn on its own
- JUSTIFY or fix every SOFT finding; the sidecar tolerates them, the gate may not
- RE-RUN the sidecar after fixing, so the findings you closed are proven closed

## Help
> IF the invocation carries `--help` or `-h`, this section is the whole turn:

```text
SKILL: /plugin:name
DESCRIPTION: <the `description` frontmatter, verbatim>
POSTURE: <the readme index's keyword for this skill>
FLAGS:
- --flag: <what it changes, in the telemetry bullet's own words>
ARGUMENTS:
- <arg>: <what it names>
ARTIFACT: <the `metadata.artifact` path, or none>
OUTPUT: <what lands in the turn: an audit entry, a handover block, an inline report>
SPEC: <this doc's own path>
```

- every field prints, in this order; one with nothing to say prints `none`
- every value is COPIED from the source named beside it, never composed fresh
- ask what they are actually trying to do, and what they have already tried
- name the flag or the sibling skill that fits their answer, then STOP
- run no step, write no file, and never fall through to step 1

## Subagent Style
```!
awk 'NR>1 && /^---$/ {p=1; next} p' "${CLAUDE_PLUGIN_ROOT}/subagent-styles/operator.md"
```

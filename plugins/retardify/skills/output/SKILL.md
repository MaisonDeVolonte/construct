---
name: output
model: opus
effort: high
license: MIT
compatibility: requires bash, git
description: output style linter run by the stop hook, or on a reply file or stdin via <path> argument
argument-hint: "[--help] <path>|-"
disable-model-invocation: true
metadata:
  kind: trigger
---

**the reply graded against the spec:** findings carry the spec's own addresses, never prose
- grades the mechanically checkable rules: B1 markup, B2 prose, B6 shapes, C2 width, C8 ceiling
- HARD findings block a stop-hook turn; SOFT ones only ride along with a hard one
- reads the width and the ceiling from the style copy beside it, so the spec stays the one source
- C10 exemptions hold: code, terminal output, quoted content and tables are never graded
- the stop action `retardify-output.sh` is its one automated caller, and degrades without it

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

- line 0 names a whole-reply finding: an unclosed fence, the ceiling, or the prose tolerance
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

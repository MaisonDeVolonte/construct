---
name: guide
model: fable
effort: max
license: MIT
compatibility: requires bash, git
description: distill a completed plan into a perfect-world build guide, then validate it (saves guide to .construct/)
argument-hint: "[--help] <path> [--test]"
disable-model-invocation: true
metadata:
  artifact: .construct/retardify/guide/
---

# Instructions

## Telemetry
```!
"${CLAUDE_PLUGIN_ROOT}"/skills/guide/guide.sh "$ARGUMENTS"
echo "sidecar exit: $?"
```
- `help: requested` → the run was refused before it started; `## Help` below is the whole turn
- it already ran, so there is no command to issue
- fail (`sidecar exit` > 0) → abort and report the raw terminal error inside a markdown code block
- `completed: no` → STOP and name the open boxes; a guide distills finished work only
- `collision: yes` → a guide already covers this plan; ASK whether to replace it, then WAIT
- success (`sidecar exit` = 0) → take `target` from the telemetry and continue to step 1

1. read the whole source plan, notes included, and extract the straight path
  - the checklist says what landed and the notes say what it cost; keep only what the finish needs
  - re-derive the order a builder follows knowing everything the plan learned, then sort by it
  - drop every probe, reversal, workaround and repair; a perfect world has nothing to recover from
  - where the plan branched, keep the branch that won, stated as the only way it goes

2. write `[target]` in the shape defined under `## the shape` below
  - imperative voice, present tense: `write the manifest`, never `we wrote` or `you might`
  - every step assumes the one before it landed clean, so no step checks, hedges or retries
  - lines carry a single clause, capped at 100 characters, and never wrap

3. validate what landed, then show it and STOP
  ```bash
  plugins/retardify/skills/guide/guide.sh --check [target]
  ```
  - FIX every ERROR and re-run; a guide that fails its own validator is not saved work
  - show the saved guide inline, then STOP

    NEVER carry a caveat over from the plan, and never invent one
    the plan records the real run; the guide states the ideal one

## the shape
> the spec this skill writes against; the validator below grades what landed

**the file:** `.construct/retardify/guide/<title>.md`, kebab-case, named by the plan it distills
- one per completed plan, replaced rather than dated, since the ideal path has no history
- sections run in this order: requires, steps, done
- maximally concise: every line moves the build forward, or it goes
- no risks, no notes, no readiness, no alternatives; all superfluous under ideal conditions
- scrub client names, tokens, and other sensitive detail before it lands in a commit

# GUIDE: Short Title
one line: what exists when the last step is done

## Requires
- one hyphen bullet per prerequisite: a tool, a version floor, or an access

## Steps

### 1. Stage name
1. one imperative directive per line, single clause, numbered from 1
2. each stage finishes what the next one stands on

### 2. Next stage
1. stages climb by one and sort so no stage reopens an earlier stage's work

## Done
- one observable end-state check per hyphen bullet, provable by a command or a glance

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

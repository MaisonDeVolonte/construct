---
name: manual
model: fable
effort: max
license: MIT
compatibility: requires bash, git
description: Distill a completed plan into a perfect-world build manual in .construct/retardify/manual/, then validate it.
argument-hint: "<plan>"
disable-model-invocation: true
metadata:
  kind: trigger
  artifact: .construct/retardify/manual/
---
**/retardify:manual:** the frontmatter blocks every path except an explicit invocation
- intakes a completed `/retardify:plan` file from `.construct/retardify/plan/` and outputs the ideal path
- a perfect-world rewrite: the build as it goes when every step lands clean on the first try
- assumes the likeliest case at every fork; the dead ends and repairs stay in the plan

## voice

```!
awk 'NR>1 && /^---$/ {p=1; next} p' "${CLAUDE_PLUGIN_ROOT}/output-styles/operator.md"
```

- the block above already ran, and it is the output contract for this response
- it holds for this turn even when the user's active output style is something else
- an empty block means the plugin has no style file; continue, since voice never gates the work

## telemetry

```!
"${CLAUDE_PLUGIN_ROOT}"/skills/manual/manual.sh $ARGUMENTS
echo "sidecar exit: $?"
```

1. read the block above; it already ran, so there is no command to issue
  - fail (`sidecar exit` > 0) → abort and report the raw terminal error inside a markdown code block
  - `completed: no` → STOP and name the open boxes; a manual distills finished work only
  - `collision: yes` → a manual already covers this plan; ASK whether to replace it, then WAIT
  - success (`sidecar exit` = 0) → take `target` from the telemetry and continue to step 2

2. read the whole source plan, notes included, and extract the straight path
  - the checklist says what landed and the notes say what it cost; keep only what the finish needs
  - re-derive the order a builder follows knowing everything the plan learned, then sort by it
  - drop every probe, reversal, workaround and repair; a perfect world has nothing to recover from
  - where the plan branched, keep the branch that won, stated as the only way it goes

3. write `[target]` in the shape defined under `## the shape` below
  - imperative voice, present tense: `write the manifest`, never `we wrote` or `you might`
  - every step assumes the one before it landed clean, so no step checks, hedges or retries
  - lines carry a single clause, capped at 100 characters, and never wrap

4. validate what landed, then show it and STOP
  ```bash
  plugins/retardify/skills/manual/manual.sh --check [target]
  ```
  - FIX every ERROR and re-run; a manual that fails its own validator is not saved work
  - show the saved manual inline, then STOP

    NEVER carry a caveat over from the plan, and never invent one
    the plan records the real run; the manual states the ideal one

## the shape
> the spec this skill writes against; the validator below grades what landed

**the file:** `.construct/retardify/manual/<title>.md`, kebab-case, named by the plan it distills
- one per completed plan, replaced rather than dated, since the ideal path has no history
- sections run in this order: requires, steps, done
- maximally concise: every line moves the build forward, or it goes
- no risks, no notes, no readiness, no alternatives; all superfluous under ideal conditions
- scrub client names, tokens, and other sensitive detail before it lands in a commit

# MANUAL: Short Title
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

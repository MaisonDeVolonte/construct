---
name: write-plan
description: Turn work into a staged plan in docs/plans/, with readiness tables, then validate it.
argument-hint: <goal>
disable-model-invocation: true
metadata:
  kind: trigger
---
**/write-plan:** the frontmatter blocks every path except an explicit invocation
- written before complex or architectural work, never after it
- the checklist is the deliverable: numbered stages, each shipping as its own pr
- readiness is what gates it, since a stage nobody can run is a stage that does not start

## telemetry

```!
"${CLAUDE_PLUGIN_ROOT}"/skills/write-plan/write-plan.sh $ARGUMENTS
echo "sidecar exit: $?"
```

1. read the block above; it already ran, so there is no command to issue
  - fail (`sidecar exit` > 0) → abort and report the raw terminal error inside a markdown code block
  - `collision: yes` → STOP and name the file already holding that slug; never overwrite a plan
  - success (`sidecar exit` = 0) → take `target` from the telemetry and continue to step 2

2. gather what the plan rests on before drafting a line of it
  - read the repo for the motivation, the obstacle, the constraint and the guardrails
  - ASK the user for whatever the repo cannot answer, in one round, then WAIT for the answers
  - verify any claim carrying a number before it lands, or leave the number out

3. write `[target]` in the shape `AGENTS/skills/doc-plans/SKILL.md` defines
  - sections in order: context, goal, solution, risks, checklist, readiness, notes
  - stages are numbered `### <n>. <name>`, run in sequence, and each ships as its own pr
  - risks sort by blast radius and irreversibility, never by likelihood
  - readiness states feasibility only; a row proposing new work belongs in the checklist
  - every permission row is quoted exactly from a settings file, or labelled a proposal
  - notes are numbered so every `(see #x)` resolves, and are the only place verbosity belongs

4. validate what landed, then show it and STOP
  ```bash
  AGENTS/skills/doc-plans/doc-plans.sh [target]
  ```
  - FIX every ERROR and re-run; a plan that fails its own validator is not saved work
  - show the saved plan inline, then STOP

    NEVER start stage 1 in the same turn, and never offer to; the plan IS the deliverable
    it gets read, argued with and edited before anything is built against it

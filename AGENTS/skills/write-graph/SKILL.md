---
name: write-graph
description: Turn a goal into a fan-out spec prompt in docs/graphs/, then validate it against its spec.
argument-hint: <goal>
disable-model-invocation: true
metadata:
  kind: trigger
---
**/write-graph:** the frontmatter blocks every path except an explicit invocation
- turns a goal into a fan-out spec: the prompt a fresh session executes to do the work
- a spec states constraints, never plan steps; the checkboxes belong to whatever it produces
- writes one file and stops; the fan-out itself begins only on your explicit go

## telemetry

```!
"${CLAUDE_PLUGIN_ROOT}"/skills/write-graph/write-graph.sh $ARGUMENTS
echo "sidecar exit: $?"
```

1. read the block above; it already ran, so there is no command to issue
  - fail (`sidecar exit` > 0) → abort and report the raw terminal error inside a markdown code block
  - `collision: yes` → STOP and name the file already holding that slug; never overwrite a spec
  - success (`sidecar exit` = 0) → take `target` from the telemetry and continue to step 2

2. gather what the spec cannot invent
  - read the repo for every fact the goal depends on
  - ASK the user for whatever the repo cannot answer, in one round, then WAIT for the answers
  - a fact from neither the repo nor the user does not exist, and never reaches `context`

3. write `[target]` in the shape `AGENTS/skills/doc-graphs/SKILL.md` defines
  - seven fields in order: goal, context, done when, fan out, rules, verify, output
  - the key sits at column 1 and its value at column 15, continuation lines indented to match
  - `fan out` names 2-5 agents, then closes with one unnumbered return shape they all share
  - `rules` bind every fanned agent, and name what stays out of scope
  - `output` names the artifact executing this spec must produce, which defaults to a plan

4. validate what landed, then show it and STOP
  ```bash
  AGENTS/skills/doc-graphs/doc-graphs.sh [target]
  ```
  - FIX every ERROR and re-run; a spec that fails its own validator is not saved work
  - show the saved spec inline, then STOP

    NEVER begin the fan-out in the same turn, and never offer to; the spec IS the deliverable
    a fresh session executes it, which is the whole reason it is a file rather than a message

---
name: write-guide
description: Turn a shipped feature into a build guide in docs/guides/, then validate it.
argument-hint: <feature>
disable-model-invocation: true
metadata:
  kind: trigger
---
**/write-guide:** the frontmatter blocks every path except an explicit invocation
- written after a feature ships, to build a mental model of how it actually works
- a map and not a textbook: the file list in build order IS the guide
- one per feature or workflow, replaced rather than dated, since it describes what is true now

## telemetry

```!
"${CLAUDE_PLUGIN_ROOT}"/skills/write-guide/write-guide.sh $ARGUMENTS
echo "sidecar exit: $?"
```

1. read the block above; it already ran, so there is no command to issue
  - fail (`sidecar exit` > 0) → abort and report the raw terminal error inside a markdown code block
  - `collision: yes` → a guide already covers this feature; ASK whether to replace it, then WAIT
  - success (`sidecar exit` = 0) → take `target` from the telemetry and continue to step 2

2. read the feature before describing it
  - read every file the feature touches, and follow the imports rather than guessing at them
  - work out the order somebody should read them in to understand it from nothing
  - that order is ideal-build order, which is neither alphabetical nor the order you opened them

3. write `[target]` in the shape `AGENTS/skills/doc-guides/SKILL.md` defines
  - one line per file: what it is, why it sits in that spot, one clause max
  - `Model` is the single idea to walk away with, in 1-3 lines and no more
  - `Pattern` is how to build the next similar thing, using this feature as the reference
  - lines carry a single clause, capped at 100 characters, and never wrap

4. validate what landed, then show it and STOP
  ```bash
  AGENTS/skills/doc-guides/doc-guides.sh [target]
  ```
  - FIX every ERROR and re-run; a guide that fails its own validator is not saved work
  - show the saved guide inline, then STOP

    NEVER refactor the feature you were asked to describe, and never offer to
    a guide that quietly improves its subject is describing something that no longer exists

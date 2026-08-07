---
name: guide
description: Turn a shipped feature into a build guide in .operator/guides/, then validate it.
argument-hint: <feature>
disable-model-invocation: true
metadata:
  kind: trigger
---
**/retardify:guide:** the frontmatter blocks every path except an explicit invocation
- written after a feature ships, to build a mental model of how it actually works
- a map and not a textbook: the file list in build order IS the guide
- one per feature or workflow, replaced rather than dated, since it describes what is true now

## telemetry

```!
"${CLAUDE_PLUGIN_ROOT}"/skills/guide/guide.sh $ARGUMENTS
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

3. write `[target]` in the shape defined under `## the shape` below
  - one line per file: what it is, why it sits in that spot, one clause max
  - `Model` is the single idea to walk away with, in 1-3 lines and no more
  - `Pattern` is how to build the next similar thing, using this feature as the reference
  - lines carry a single clause, capped at 100 characters, and never wrap

4. validate what landed, then show it and STOP
  ```bash
  plugins/retardify/skills/guide/guide.sh --check [target]
  ```
  - FIX every ERROR and re-run; a guide that fails its own validator is not saved work
  - show the saved guide inline, then STOP

    NEVER refactor the feature you were asked to describe, and never offer to
    a guide that quietly improves its subject is describing something that no longer exists

## the shape
> the spec this skill writes against; the validator below grades what landed

**the file:** `.operator/guides/<feature>.md`, kebab-case, one per feature or workflow
- written on request, after a feature ships, to build a mental model of how it works
- files are listed in ideal-build order, never alphabetical and never touched-order
- maximally concise, roadmap-style language — a map, not a textbook
- lines carry a single clause, capped at 100 characters, and never wrap
- scrub client names, tokens, and other sensitive detail before it lands in a commit

# GUIDE: Short Title
one line 'big idea' description of the topic/feature/concept the guide covers

- [ ] one line per file: what it is, why it's in this spot, one clause max

*example:*
> - [ ] `types.ts` is the shape everything downstream returns; read this first, always
> - [ ] `apis/source.ts` does raw fetch only, no formatting; the "one call, cache it" pattern
> - [ ] `aggregate.ts` does raw data becomes UI-ready strings here; the fail-soft pattern lives here
> - [ ] `Widget.tsx` is dumb consumer; if this file surprises you, the layer below did its job wrong

## Model
the one idea to walk away with, 1-3 lines, no more

*example:*
> raw source → per-source derivation → aggregate (format + cache + fail-soft) → dumb UI.
> every new stat repeats this exact chain — nothing skips a layer, nothing shares a fetch.

## Pattern
how to build the next similar thing, using this as the reference

*example:*
> 1. add the shape to `types.ts`
> 2. build one raw source under `apis/`, one job, no formatting
> 3. derive + format + cache in `aggregate.ts`
> 4. wire the dumb UI row last

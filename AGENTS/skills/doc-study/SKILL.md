---
name: doc-study
description: Shape of a retrospective study in docs/study/, with its graded quiz.
metadata:
  kind: spec
---
**the file:** `docs/study/<feature>.md`, kebab-case, tracked in git, one per feature or workflow
- written on request, after a feature ships, to build a mental model of how it works
- files are listed in ideal-build order, never alphabetical and never touched-order
- maximally concise, roadmap-style language — a map, not a textbook
- lines carry a single clause, capped at 100 characters, and never wrap
- scrub client names, tokens, and other sensitive detail before it lands in a commit

# STUDY: Short Title
one line 'big idea' description of the topic/feature/concept to be studied

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

```text
VERIFY - not part of the artifact
- RUN `AGENTS/skills/doc-study/doc-study.sh` once the study is written; pass a path to scope the run
- FIX every ERROR, since each one breaks a rule this spec states outright
- STOP on a `secret` finding and ask the user before truncating it; the key needs rotating first
- JUSTIFY or fix every WARN; the sidecar tolerates them, the next reader may not
- ANSWER the checklist it prints, since those rules are the ones no script can judge
```

# AGENT PLAN: Operation Perfect Planning
make the plans template tell the truth, by fixing the example that currently contradicts it

## Context
why the work exists, in briefing order
- the plans template gained a readiness section, proven only against synthetic fixtures
- the one worked example in `docs/plans/` predates its template and fails twelve checks
- the readme requires a summary that the template's section list leaves out (see #1)
- a template whose only example violates it teaches the violation, not the rule
- this plan is the first written through the readiness section, so it is the proof

## Goal
every plan in the repo passes its own sidecar, example included
```text
docs/plans/
  2026-07-29-operation-paper-trail.md         conforming, tracked, green
  2026-07-31-operation-perfect-planning.md    this plan, green
AGENTS/templates/
  plans.md    section list closes with readiness, notes, summary
  plans.sh    summary accepted last, present or absent
```

## Solution
the strategy: one decision per line
- make summary an optional trailing section, rather than deleting the readme rule (see #1)
- fix the example in place, so the history behind it survives the rename (see #2)
- restructure its flat checklist into the two stages it actually shipped as
- classify this plan's own items honestly, even where the answer is unflattering (see #3)

## Risks
sorted by blast radius and irreversibility
- `lost history` if the example is rewritten as a new file instead of renamed
- `false green` if the sidecar is loosened to pass the example, rather than the example fixed
- `silent drift` if summary lands optional and every plan then quietly skips it (see #4)
- `costs an hour` if renumbering the example's notes breaks references that already resolve

## Checklist

### 1. Settle the summary rule
- [ ] decide whether a trailing summary is required or optional, and record it (see #1)
- [ ] teach plans.sh to accept a plan with or without the trailing section
- [ ] prove both shapes against a fixture pair, one with a summary and one without

### 2. Fix the worked example
- [ ] rename the example with git mv, carrying its 2026-07-29 date (see #2)
- [ ] move the blockquote below the summary line, leaving line three blank
- [ ] unwrap the context and solution paragraphs into single clause bullets
- [ ] add a goal section holding a tree of the three archive directories
- [ ] group the seven checklist items into the two stages they shipped as
- [ ] move future work under the checklist, as deferred work
- [ ] add a readiness section, with blockers reading none
- [ ] resolve the eight orphan notes, by reference or by deletion (see #5)

### Deferred Work
- [ ] a study covering the sidecar family, the one thing with no artifact of its own
- [ ] a ci job running every sidecar against its own docs directory

## Readiness

### Blockers
unrelated tasks to clear before starting this plan, if any:

| task | blocks | where |
|---|---|---|
| 1. none | — | the only other plan is closed, so nothing gates a start |

### Agents
how each stage's checklist items are split by who can run them:

| stage | agentic | human-only | gated | note # |
|---|---|---|---|---|
| 1. Settle the summary rule | 2 | 1 | — | see #3 |
| 2. Fix the worked example | — | — | 8 | see #3 |

### Permissions
suggested rules to set in order for agents to work reliably:

| rule | layer | scope | suggestion | why |
|---|---|---|---|---|
| 1. `Write(docs/**)` | permissions | project | add to allow | proposal; every write prompts |
| 2. `Edit(docs/**)` | permissions | project | add to allow | proposal; stage 2 edits prompt |
| 3. `Bash(git mv *)` | permissions | project | add to allow | proposal; the only git mv needed |

## Notes
1. the readme says to complete a plan with a summary, and the template's order omits one
2. `git mv` keeps the rename a rename, so `git log --follow` still reaches the original
3. stage 2 is entirely gated because `docs/**` sits in neither the allow nor the deny list
4. an optional section is one nobody writes, so the sidecar should warn on a closed plan
5. eight notes in the example are referenced by nothing, which is a warning per note


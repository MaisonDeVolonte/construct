---
name: todo
description: Scan repo, docs and logs for what to work on next, saved to file.
disable-model-invocation: true
metadata:
  kind: trigger
---
**/retardify:todo:** Run ONLY on explicit `/retardify:todo` command
- surfaces work opportunities from three streams: deterministic reference checks, doc-vs-reality reconciliation, and recent agent logs
- categorizes every opportunity on an urgent/important matrix
- it is asked when the user has lost their bearings, so the deliverable is somewhere to start
- broken references are one signal among many, never the point; a clean scan still owes leads
- streams 2 and 3 carry the judgement, so a run reporting only sidecar counts has skipped the work

## telemetry

```!
"${CLAUDE_PLUGIN_ROOT}"/skills/todo/todo.sh
echo "sidecar exit: $?"
```

1. read the block above; it already ran, so there is no command to issue
  - report-only; it never fails the run — capture its telemetry (broken references + code markers)

2. reconcile docs against reality — run this block once per objective, one objective at a time:
  - **read:** the source of truth (the code, dirs, or config the doc describes)
  - **search:** where the doc makes claims about it
  - **reconcile:** does every claim still match reality?
  - **flag:** each drift as an opportunity (note the file and the mismatch)

  objectives (one at a time):
  - **README.md** — does it still describe the project, stack, and setup accurately?
  - **AGENTS.md** — do its prose rules still hold (naming, css, imports, mirroring, etc.)?
  - **plugins/\*/** — does each skill's doc still match its own sidecar's flags and behavior?

3. read the 5 most recent agent logs in `.operator/logs/`, the shape `/retardify:log` defines
  - extract observations, pain points, unfinished tasks, recurring bugs, or architectural ideas

4. merge all three streams, dedupe, and evaluate against the urgent/important matrix:
  - **Q1 (urgent and important):** broken references, blockers, doc/code drift that misleads
  - **Q2 (urgent but not important):** code markers, minor configuration fixes, trivial tool warnings
  - **Q3 (not urgent but important):** refactoring, tech debt, architectural hygiene, core feature work
  - **Q4 (not urgent or important):** overly ambitious refactors, nice-to-haves, out-of-scope ideas

5. generate the final report:
  ```markdown
  # /retardify:todo report
  *synthesized from sidecar findings, doc reconciliation, and the last 5 agent logs (YYYY-MM-DD to YYYY-MM-DD)*

  ## observations
  - hyphen-delimited list of bullets

  ## opportunities
  **urgent and important:**
  - hyphen-delimited list of bullets

  **urgent but not important:**
  - hyphen-delimited list of bullets

  **not urgent but important:**
  - hyphen-delimited list of bullets

  **not urgent or important:**
  - hyphen-delimited list of bullets
  ```

6. THEN append the same report to the insights file (see `plugins/retardify/skills/todo/SKILL.md`)
  ```text
  - the sidecar reports the target but never creates it; take it from the telemetry header:
  - CREATE the file first if it does not exist, with `# <insights_file>` as its only line
    - `insights_file` is the path, `insights_time` is the heading timestamp
    - `insights_count` is how many reports the file already holds, so this one is #(insights_count + 1)
  - append a new `## Insight #N: YYYY-MM-DD HH:MM` section, never overwrite an earlier report
  - write the report as delivered to the user, minus the raw sidecar dump
  - an opportunity that recurs across dated files is a finding in itself; restate it, never edit the older report
  ```

## the shape
> the spec this skill writes against; the validator below grades what landed

# .operator/todos/YYYY-MM-DD.md
one file per day, appended to by `/retardify:todo` and nothing else:

- a report captures the opportunity surface at a moment in time, never edited after the fact
- `observations` are what the three streams found; `opportunities` are what to do about it
- an opportunity sorts onto the urgent/important matrix, and names the file it touches
- an opportunity that recurs across dated files is a finding; restate it, never edit the older one
- a Q1 entry that survives three reports has stopped being urgent in practice, so say so
- skip the raw sidecar dump; keep the read of it, not the printout
- lines hold a single clause, fact or action, capped at 100 characters
- scrub client names, tokens, and other sensitive detail before it lands in a commit

## Insight #1: YYYY-MM-DD HH:MM

### sources
which streams fed this report, and the log range read

*example:*
> sidecar: 3 broken refs, 6 markers | docs reconciled: README, AGENTS.md | logs: 2026-07-24 to 2026-07-29

### observations
what the three streams actually surfaced:
- hyphen-delimited list of bullets

*example:*
> `review.sh` greps `content/**`, a path that no longer exists in this repo
> README documents a `.gitkeep` scaffold that `.gitignore` no longer preserves
> logs mention the same hook-testing gap on 3 separate days

### opportunities
**urgent and important:**
- broken references, blockers, doc/code drift that misleads

**urgent but not important:**
- code markers, minor configuration fixes, trivial tool warnings

**not urgent but important:**
- refactoring, tech debt, architectural hygiene, core feature work

**not urgent or important:**
- overly ambitious refactors, nice-to-haves, out-of-scope ideas

### carried
opportunities restated from an earlier report, with how many reports they have survived

*example:*
> hook test coverage — carried 3 reports, still Q1 on paper, evidently not urgent in practice

## Insight #2: repeat the above format for each `/retardify:todo` run on the same day
never edit an earlier report; a recurring opportunity is signal about what keeps getting skipped

---
name: git-insights
description: Scan repo, docs and logs for what to work on next, saved to file.
disable-model-invocation: true
metadata:
  kind: trigger
---
**@git-insights:** Run ONLY on explicit `@git-insights` command
- surfaces work opportunities from three streams: deterministic reference checks, doc-vs-reality reconciliation, and recent agent logs
- categorizes every opportunity on an urgent/important matrix
- it is asked when the user has lost their bearings, so the deliverable is somewhere to start
- broken references are one signal among many, never the point; a clean scan still owes leads
- streams 2 and 3 carry the judgement, so a run reporting only sidecar counts has skipped the work

## telemetry

```!
"${CLAUDE_PLUGIN_ROOT}"/skills/git-insights/git-insights.sh
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
  - **AGENTS/skills/\*/** — does each skill's doc still match its own sidecar's flags and behavior?

3. read the 5 most recent agent logs in `docs/logs/`, the shape `AGENTS/skills/doc-logs/SKILL.md` defines
  - extract observations, pain points, unfinished tasks, recurring bugs, or architectural ideas

4. merge all three streams, dedupe, and evaluate against the urgent/important matrix:
  - **Q1 (urgent and important):** broken references, blockers, doc/code drift that misleads
  - **Q2 (urgent but not important):** code markers, minor configuration fixes, trivial tool warnings
  - **Q3 (not urgent but important):** refactoring, tech debt, architectural hygiene, core feature work
  - **Q4 (not urgent or important):** overly ambitious refactors, nice-to-haves, out-of-scope ideas

5. generate the final report:
  ```markdown
  # @git-insights report
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

6. THEN append the same report to the insights file (see `AGENTS/skills/doc-insights/SKILL.md`)
  ```text
  - the sidecar reports the target but never creates it; take it from the telemetry header:
  - CREATE the file first if it does not exist, with `# <insights_file>` as its only line
    - `insights_file` is the path, `insights_time` is the heading timestamp
    - `insights_count` is how many reports the file already holds, so this one is #(insights_count + 1)
  - append a new `## Insight #N: YYYY-MM-DD HH:MM` section, never overwrite an earlier report
  - write the report as delivered to the user, minus the raw sidecar dump
  - an opportunity that recurs across dated files is a finding in itself; restate it, never edit the older report
  ```

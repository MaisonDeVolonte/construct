```javascript
/**
 * =========================================================
 * @file gitinsights.md - read-only opportunity-scan trigger
 * =========================================================
 * @description
 * - ran only on explicit `@gitinsights` command; read-only, never mutates tracked files
 * - runs `AGENTS/git/gitinsights.sh` for deterministic findings (broken references, code markers)
 * - reconciles `README.md`/`AGENTS.md`/trigger docs against actual repo reality
 * - reads the 5 most recent `docs/logs/` entries for unresolved observations
 * - merges all three streams into an urgent/important opportunity matrix
 * - appends that report to `docs/insights/YYYY-MM-DD.md`, one file per day, many reports per file
 * @see AGENTS.md, AGENTS/templates/git.md, AGENTS/git/gitinsights.sh, docs/logs/, AGENTS/templates/logs.md, AGENTS/templates/insights.md, docs/insights/
 */
```

**@gitinsights:** Run ONLY on explicit `@gitinsights` command
- surfaces work opportunities from three streams: deterministic reference checks, doc-vs-reality reconciliation, and recent agent logs
- categorizes every opportunity on an urgent/important matrix

1. run the sidecar for deterministic findings
  ```bash
  AGENTS/git/gitinsights.sh
  ```
  - report-only; it never fails the run — capture its telemetry (broken references + code markers)

2. reconcile docs against reality — run this block once per objective, one objective at a time:
  - **read:** the source of truth (the code, dirs, or config the doc describes)
  - **search:** where the doc makes claims about it
  - **reconcile:** does every claim still match reality?
  - **flag:** each drift as an opportunity (note the file and the mismatch)

  objectives (one at a time):
  - **README.md** — does it still describe the project, stack, and setup accurately?
  - **AGENTS.md** — do its prose rules still hold (naming, css, imports, mirroring, etc.)?
  - **/AGENTS/\*.md ↔ /AGENTS/\*.sh** — does each trigger's doc still match its script's flags and behavior?

3. read the 5 most recent agent memory log files in `docs/logs/`
  - extract observations, pain points, unfinished tasks, recurring bugs, or architectural ideas

4. merge all three streams, dedupe, and evaluate against the urgent/important matrix:
  - **Q1 (urgent and important):** broken references, blockers, doc/code drift that misleads
  - **Q2 (urgent but not important):** code markers, minor configuration fixes, trivial tool warnings
  - **Q3 (not urgent but important):** refactoring, tech debt, architectural hygiene, core feature work
  - **Q4 (not urgent or important):** overly ambitious refactors, nice-to-haves, out-of-scope ideas

5. generate the final report:
  ```markdown
  # @gitinsights report
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

6. THEN append the same report to the insights file (see `AGENTS/templates/insights.md`)
  ```text
  - the sidecar reports the target but never creates it; take it from the telemetry header:
  - CREATE the file first if it does not exist, with `# <insights_file>` as its only line
    - `insights_file` is the path, `insights_time` is the heading timestamp
    - `insights_count` is how many reports the file already holds, so this one is #(insights_count + 1)
  - append a new `## Insight #N: YYYY-MM-DD HH:MM` section, never overwrite an earlier report
  - write the report as delivered to the user, minus the raw sidecar dump
  - an opportunity that recurs across dated files is a finding in itself; restate it, never edit the older report
  ```

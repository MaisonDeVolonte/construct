```javascript
/**
 * ==================================================
 * @file insights.md - opportunity report template
 * ==================================================
 * @description
 * - tracked in git, one insights file per day, appended across runs
 * - scrub client names, tokens, and other sensitive detail before it lands in a commit
 * - written by `@gitinsights` only, appended each run, many reports per file
 * - `reports` capture the opportunity surface at a moment in time, never edited after the fact
 * - `observations` are what the three streams found; `opportunities` are what to do about it
 * - `opportunities` sort onto the urgent/important matrix, and name the file they touch
 * - `lines` should contain a single clause/fact/action, limited to 100 characters
 * - skip the raw sidecar dump; keep the read of it, not the printout
 * - an opportunity that recurs across dated files is a finding; restate it, never edit the older report
 * - a Q1 entry that survives three reports has stopped being urgent in practice, say so
 * - `AGENTS/templates/insights.sh` validates a report against every rule above a script can judge
 * @see AGENTS.md, AGENTS/templates/insights.sh, AGENTS/git/gitinsights.md, docs/insights/
 */
```

# docs/insights/YYYY-MM-DD.md

## Insight #1: YYYY-MM-DD HH:MM

### sources
which streams fed this report, and the log range read

*example:*
> sidecar: 3 broken refs, 6 markers | docs reconciled: README, AGENTS.md | logs: 2026-07-24 to 2026-07-29

### observations
what the three streams actually surfaced:
- hyphen-delimited list of bullets

*example:*
> `githonest.sh` greps `content/**`, a path that no longer exists in this repo
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

## Insight #2: repeat the above format for each `@gitinsights` run on the same day
never edit an earlier report; a recurring opportunity is signal about what keeps getting skipped

```text
VERIFY - not part of the artifact
- RUN `AGENTS/templates/insights.sh` once the report is appended; pass a path to scope the run
- FIX every ERROR, since each one breaks a rule stated in the header above
- STOP on a `secret` finding and ask the user before truncating it; the key needs rotating first
- JUSTIFY or fix every WARN; the sidecar tolerates them, the next reader may not
- ANSWER the checklist it prints, since those rules are the ones no script can judge
```

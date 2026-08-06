---
name: doc-insights
description: Shape of an opportunity scan in docs/insights/, written by /git-insights.
metadata:
  kind: spec
---
# docs/insights/YYYY-MM-DD.md
one file per day, appended to by `@git-insights` and nothing else:

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
> `git-honest.sh` greps `content/**`, a path that no longer exists in this repo
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

## Insight #2: repeat the above format for each `@git-insights` run on the same day
never edit an earlier report; a recurring opportunity is signal about what keeps getting skipped

```text
VERIFY - not part of the artifact
- RUN `AGENTS/skills/doc-insights/doc-insights.sh` once the report is appended; pass a path to scope the run
- FIX every ERROR, since each one breaks a rule this spec states outright
- STOP on a `secret` finding and ask the user before truncating it; the key needs rotating first
- JUSTIFY or fix every WARN; the sidecar tolerates them, the next reader may not
- ANSWER the checklist it prints, since those rules are the ones no script can judge
```

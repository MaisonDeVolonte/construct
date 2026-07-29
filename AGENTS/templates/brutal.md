```javascript
/**
 * ==============================================
 * @file brutal.md - brutal scorecard template
 * ==============================================
 * @description
 * - gitignored, local-only, never committed, one brutal file per day
 * - written by `@gitbrutal` only, appended each run, many scorecards per file
 * - `scorecards` capture the doc-vs-reality gap at a moment in time, never edited after the fact
 * - `grades` are A-F per lane; strong infra grades CANNOT mask weak app/test ones
 * - `lines` should contain a single clause/fact/action, limited to 100 characters
 * - name specific files, claims, and commits; an unfalsifiable criticism is worthless
 * - skip the raw telemetry dump; keep the read of it, not the printout
 * - never soften a written scorecard, and never re-grade an older one to match a newer mood
 * - grade drift across dated files is the point; a lane stuck at D is the signal
 * @see AGENTS.md, AGENTS/git/gitbrutal.md, docs/brutal/
 */
```

# docs/brutal/YYYY-MM-DD.md

## Brutal #1: YYYY-MM-DD HH:MM

### reality check
each documented claim, followed by what the telemetry actually shows:
- [claim from docs]: [harsh reality]

*example:*
> README claims "strict commit types": 31 of the last 100 commits are bare `update`
> AGENTS.md claims hooks are tested: zero test files touch `AGENTS/hooks/`

### effort vs output
where the time actually went, in one or two lines

*example:*
> 4 days and 30 commits on github actions, 2 hours on the ui components anyone will see

### risk & maintenance traps
specific files, ignored rules, or architectural landmines

*example:*
> `gitbrutal.sh` greps `content/**` for mirrors, a path that no longer exists
> 6 unresolved TODOs, oldest is 41 days

### grades
- **infra/tooling:** A-F
- **app/features:** A-F
- **tests/reality:** A-F

**verdict:** one unapologetic sentence on the actual state of the codebase

*example:*
> **verdict:** an immaculate build system wrapped around software nobody has proven works

## Brutal #2: repeat the above format for each `@gitbrutal` run on the same day
never edit an earlier scorecard; a grade that has not moved in a week is the finding

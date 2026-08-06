---
name: doc-honest
description: Shape of an adversarial graded scorecard in docs/honest/, written by /git-honest.
metadata:
  kind: spec
---
# docs/honest/YYYY-MM-DD.md
one file per day, appended to by `@git-honest` and nothing else:

- a scorecard captures the doc-vs-reality gap at a moment in time, never edited after the fact
- grades are A-F per lane, and strong infra grades CANNOT mask weak app or test ones
- name specific files, claims, and commits; an unfalsifiable criticism is worthless
- skip the raw telemetry dump; keep the read of it, not the printout
- never soften a written scorecard, and never re-grade an older one to match a newer mood
- grade drift across dated files is the point; a lane stuck at D is the signal
- lines hold a single clause, fact or action, capped at 100 characters
- scrub client names, tokens, and other sensitive detail before it lands in a commit

## Honest #1: YYYY-MM-DD HH:MM

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
> `git-honest.sh` greps `content/**` for mirrors, a path that no longer exists
> 6 unresolved TODOs, oldest is 41 days

### grades
- **infra/tooling:** A-F
- **app/features:** A-F
- **tests/reality:** A-F

**verdict:** one unapologetic sentence on the actual state of the codebase

*example:*
> **verdict:** an immaculate build system wrapped around software nobody has proven works

## Honest #2: repeat the above format for each `@git-honest` run on the same day
never edit an earlier scorecard; a grade that has not moved in a week is the finding

```text
VERIFY - not part of the artifact
- RUN `AGENTS/skills/doc-honest/doc-honest.sh` once the scorecard is appended; pass a path to scope the run
- FIX every ERROR, since each one breaks a rule this spec states outright
- STOP on a `secret` finding and ask the user before truncating it; the key needs rotating first
- JUSTIFY or fix every WARN; the sidecar tolerates them, the next reader may not
- ANSWER the checklist it prints, since those rules are the ones no script can judge
```

```javascript
/**
 * =========================================
 * @file audits.md - audit archive template
 * =========================================
 * @description
 * - tracked in git, one audit file per day, appended across runs
 * - scrub client names, tokens, and other sensitive detail before it lands in a commit
 * - written by `@gitaudit` only, appended each run, many audits per file
 * - `audits` capture repo state at a moment in time, so they are never edited after the fact
 * - `findings` lead with the label the trigger assigned (Ghost Branch, Local Clutter, etc)
 * - `lines` should contain a single clause/fact/action, limited to 100 characters
 * - skip the raw telemetry dump; keep the read of it, not the printout
 * - carry unresolved findings forward by restating them, never by editing the older audit
 * - err on the side of brevity, not completeness
 * - `AGENTS/templates/audits.sh` validates an audit file against every rule above a script can judge
 * @see AGENTS.md, AGENTS/templates/audits.sh, AGENTS/git/gitaudit.md, docs/audits/
 */
```

# docs/audits/YYYY-MM-DD.md

## Audit #1: YYYY-MM-DD HH:MM

### state
one or two lines on how/why the repo is in its current shape

*example:*
> 3 branches outlived their prs, main is 2 behind origin, working tree clean otherwise

### findings
numbered list of issues, each with its label and the branch/file it names:
1. **Label** — what is wrong, and on what

*example:*
> 1. **Ghost Branch** — `fix/nav-overflow` tracks a deleted upstream, 11 days stale
> 2. **Conflict Risk** — `feat/pricing` and origin/main both touch 4 files
> 3. **Local Clutter** — `chore/deps` is merged with no upstream

### resolutions
resolution steps per finding, manual command first, `@agent` shortcut second

*example:*
> 1. `git branch -d fix/nav-overflow` or `@gitempty`
> 2. `@gitgud` to merge origin/main in and surface conflicts early
> 3. `@gitempty`

### outcome
what the user actually did, appended after the fact; `pending` until then

*example:*
> pruned both ghost branches, deferred the pricing merge until the pr lands

## Audit #2: repeat the above format for each `@gitaudit` run on the same day
never edit an earlier audit; a stale finding is signal about how long it went unresolved

```text
VERIFY - not part of the artifact
- RUN `AGENTS/templates/audits.sh` once the audit is appended; pass a path to scope the run
- FIX every ERROR, since each one breaks a rule stated in the header above
- STOP on a `secret` finding and ask the user before truncating it; the key needs rotating first
- JUSTIFY or fix every WARN; the sidecar tolerates them, the next reader may not
- ANSWER the checklist it prints, since those rules are the ones no script can judge
```

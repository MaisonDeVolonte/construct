```javascript
/**
 * =========================================
 * @file audits.md - audit archive template
 * =========================================
 * @description
 * - tracked in git, one audit file per day and kind, appended across runs
 * - scrub client names, tokens, and other sensitive detail before it lands in a commit
 * - written by any `@*audit` trigger, appended each run, many audits per file
 * - the kind in the filename and the kind in each heading must match, so one archive reads as one
 * - this file owns the shape a validator can check; each sidecar owns the fields inside an entry
 * - `audits` capture repo state at a moment in time, so they are never edited after the fact
 * - `findings` lead with the label the trigger assigned (Ghost Branch, Local Clutter, etc)
 * - `lines` are hyphen bullets holding a single clause/fact/action, limited to 100 characters
 * - `telemetry` closes each entry with the raw run, fenced, so every claim above it is checkable
 * - carry unresolved findings forward by restating them, never by editing the older audit
 * - err on the side of brevity, not completeness
 * - `AGENTS/templates/audits.sh` validates an audit file against every rule above a script can judge
 * @see AGENTS.md, AGENTS/templates/audits.sh, AGENTS/git/gitaudit.md,
 *      AGENTS/settings/settingsaudit.md, docs/audits/
 */
```

# docs/audits/YYYY-MM-DD-<kind>.md

## <Kind> Audit #1: YYYY-MM-DD HH:MM

### state
hyphen bullets on what the run found, one clause each

*example:*
> - 3 branches carry work, 1 of them unmerged and 11 days stale
> - the trunk is level with origin and the last build passed

### findings
one bullet per issue, leading with the label the trigger assigned

*example:*
> - **Ghost Branch** — `fix/nav-overflow` tracks a deleted upstream, 11 days stale
> - **Conflict Risk** — `feat/pricing` and origin/main both touch 4 files
> - **Local Clutter** — `chore/deps` is merged with no upstream

### resolutions
one checkbox per finding, in the same order, naming a command or an `@agent` shortcut

*example:*
> - [ ] `git branch -d fix/nav-overflow` or `@gitempty`
> - [ ] `@gitgud` to merge origin/main in and surface conflicts early
> - [ ] `@gitempty`

### telemetry
the raw sidecar output, fenced and unedited, so every claim above can be checked against it

*example:*
> ```text
> --- @gitaudit telemetry ---
> current_branch: main
> staged_files: 0
> ---------------------------
> ```

## <Kind> Audit #2: repeat the above format for each run of the same kind on the same day
never edit an earlier audit; a stale finding is signal about how long it went unresolved

```text
VERIFY - not part of the artifact
- RUN `AGENTS/templates/audits.sh` once the audit is appended; pass a path to scope the run
- FIX every ERROR, since each one breaks a rule stated in the header above
- STOP on a `secret` finding and ask the user before truncating it; the key needs rotating first
- JUSTIFY or fix every WARN; the sidecar tolerates them, the next reader may not
- ANSWER the checklist it prints, since those rules are the ones no script can judge
```

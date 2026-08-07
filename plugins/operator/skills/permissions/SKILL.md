---
name: permissions
description: Replay the labelled command corpus through the real PreToolUse hook, then audit the merged permission rules for drift, dead rules and wildcards that auto-approve.
argument-hint: [--strict]
disable-model-invocation: true
metadata:
  kind: trigger
---
**/operator:permissions:** the frontmatter blocks every path except an explicit invocation
- answers one question: does the gate actually refuse what the corpus says it must refuse
- a config can read perfectly and still have a dead hook, which only a replay catches
- `/operator:settings` wraps this, so run it directly when you want the detail rather than the count

## telemetry

```!
"${CLAUDE_PLUGIN_ROOT}"/skills/permissions/permissions.sh
echo "sidecar exit: $?"
```

1. read the block above; it already ran, so there is no command to issue
  - fail (`sidecar exit` > 0) → findings exist; report them and continue to step 2
  - success (`sidecar exit` = 0) → report the clean replay and continue to step 2
  - `--strict` promotes warnings to errors, and needs a tool call since the block takes no arguments

2. read the two tiers differently, because they carry different weight
  - a tier 1 failure is measured, not inferred: the hook was fed that exact string and answered
    wrongly. an effect labelled `hook` that came back silent is a hole in the guard
  - an effect labelled `none` that came back denied is over-blocking, which costs real work
  - a tier 2 finding is structural: it reports what the files literally say, never what the
    matcher would do, so read it as a lead rather than a verdict
  - `no deny rule names X, and an allow wildcard covers it` is the one to act on first: that
    command is auto-approved today with no prompt at all

3. report inline
4. append one entry to `[audit_file]`, in the shape defined under `## the shape` below
  - the heading reads `## Permissions Audit #[next_audit]: [timestamp]`, both from the telemetry
  - `state` is what the run measured, as hyphen bullets, one clause each
  - `findings` lead with the label the sidecar printed, one bullet each, naming what it hit
  - `resolutions` are checkboxes, one per finding, in the same order
  - `telemetry` is the sidecar's whole output, fenced and unedited, pasted last
  - CREATE the file first if it does not exist, with `# <audit_file>` as its only line

5. STOP

    NEVER edit a settings file to fix a finding, and never offer to; the audit is the deliverable

    - every repair belongs in the scope its `.md` names, and is the user's to apply
    - a corpus gap is itself a finding: add the spelling you found in the wild, since coverage
      is the whole point of keeping a labelled list

## the shape` below
    - the heading reads `## Settings Audit #[next_audit]: [timestamp]`, both from the telemetry
    - `state` is the counts as hyphen bullets: scopes parsed, probes run, errors and warnings
    - `findings` lead with the label the sidecar printed, one bullet each, naming what it hit
    - `resolutions` are checkboxes, one per finding, naming the rule and the scope file it belongs in
    - `telemetry` is the sidecar's whole output, fenced and unedited, pasted last

    the labels the sidecar emits, and what each one means:

    | label | what it found |
    |----------|---------------|
    | parse    | a scope that does not parse, so every rule in it is inert |
    | drift    | an installed copy whose rules differ from its template |
    | verbs    | a path denied for read only, which a write still reaches |
    | scope    | machine detail in a committed file, or a mask the scope cannot honor |
    | hygiene  | duplicate rules, or a template that will not paste |
    | coverage | a rule with no why in the scope's `.md`, or a mirror claim that has diverged |
    | guard    | nothing protects the policy directories, so this auditor is editable |
    | probe    | a boundary that did not refuse, naming what got through |
    | wrapped  | errors from the test-permissions or test-scopes replay, naming the count |

3. report the audit inline, then STOP

    NEVER edit a settings file to fix a finding, and never offer to; the audit is the deliverable

    - a `parse` error outranks everything else, since that scope's rules are not running at all
    - a `verbs` error is only latent while no allow reaches the path, so read it with the allow list
    - a `drift` finding is a defect only when the installed copy is the stale one; check which
    - `guard` firing means the deny protecting this sidecar is absent; restore it before trusting a
      later clean run, since an editable auditor can be made to report clean
    - answer the checklist the sidecar prints, since those rules are the ones no script can judge

## the shape
> the spec this skill appends against; the validator below grades what landed

# audits/<kind>/YYYY-MM-DD.md
one file per day and per kind, appended to by every auditing trigger:

- the kind in the filename and the kind in each heading match, so one archive reads as one
- an audit captures repo state at a moment in time, so it is never edited after the fact
- carry an unresolved finding forward by restating it, never by editing the older audit
- lines are hyphen bullets holding a single clause, fact or action, capped at 100 characters
- err on the side of brevity, not completeness
- scrub client names, tokens, and other sensitive detail before it lands in a commit

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
> - [ ] `git branch -d fix/nav-overflow` or `@git-empty`
> - [ ] `@git-gud` to merge origin/main in and surface conflicts early
> - [ ] `@git-empty`

### telemetry
the raw sidecar output, fenced and unedited, so every claim above can be checked against it

*example:*
> ```text
> --- /gitgud:audit telemetry ---
> current_branch: main
> staged_files: 0
> ---------------------------
> ```

## <Kind> Audit #2: repeat the above format for each run of the same kind on the same day
never edit an earlier audit; a stale finding is signal about how long it went unresolved

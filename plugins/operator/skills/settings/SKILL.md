---
name: settings
description: Audit every settings scope for faults that stay silent until they matter, then probe the live boundary to confirm the gate is not dead.
argument-hint: [--static|--quick]
disable-model-invocation: true
metadata:
  kind: trigger
---
**/operator:settings:** the frontmatter blocks every path except an explicit invocation
- audits the merged settings stack for faults that are silent until the moment they matter
- static checks read the files: parse, drift, verb symmetry, scope placement, hygiene, guard
- live probes exercise the boundary, since a config can be perfect while the gate is dead
- never edits a settings file; every finding is handed back as the user's to apply

## telemetry

```!
"${CLAUDE_PLUGIN_ROOT}"/skills/settings/settings.sh
echo "sidecar exit: $?"
```

1. read the block above; it already ran, so there is no command to issue
  - fail (`sidecar exit` > 0) → findings exist; continue to step 2 and report them
  - success (`sidecar exit` = 0) → continue to step 2 and record the clean run
  - `--static` skips the probes and `--quick` skips the wrapped sidecars; both need a tool call,
    since the block above takes no arguments

2. append one entry to `[audit_file]`, in the shape defined under `## the shape` below
    - the heading reads `## Settings Audit #[next_audit]: [timestamp]`, both from the telemetry
    - `state` is the counts as hyphen bullets: scopes parsed, probes run, errors and warnings
    - `findings` lead with the label the sidecar printed, one bullet each, naming what it hit
    - `resolutions` are checkboxes, one per finding, naming the rule and the scope file it belongs in
    - `telemetry` is the sidecar's whole output, fenced and unedited, pasted last
    - CREATE the file first if it does not exist, with `# <audit_file>` as its only line

3. report the audit inline, then STOP

    NEVER edit a settings file to fix a finding, and never offer to; the audit is the deliverable

    - a `parse` error outranks everything else, since that scope's rules are not running at all
    - a `verbs` error is only latent while no allow reaches the path, so read it with the allow list
    - a `drift` finding is a defect only when the installed copy is the stale one; check which
    - `templates` firing means drift and hygiene had nothing to read, so a clean run proves less
    - a scope with no file at all is `/operator:sandbox` territory, not a finding to fix here
    - `guard` firing means the deny protecting this sidecar is absent; restore it before trusting a
      later clean run, since an editable auditor can be made to report clean
    - answer the checklist the sidecar prints, since those rules are the ones no script can judge

## the shape
> the artifact this skill appends to; the sidecar grades what landed on its next run

# .operator/settings/YYYY-MM-DD.md
one file per day, appended to by every deliberate run:

- the heading reads `## Settings Audit #[next_audit]: [timestamp]`, both from the telemetry
- an audit captures the stack at a moment in time, so it is never edited after the fact
- carry an unresolved finding forward by restating it, never by editing the older audit
- lines are hyphen bullets holding a single clause, capped at 100 characters
- scrub client names, tokens, and other sensitive detail before it lands in a commit

## Settings Audit #1: YYYY-MM-DD HH:MM

### state
the counts as hyphen bullets: scopes parsed, probes run, passes, errors, warnings

*example:*
> - 4 scopes parsed, carrying 435 project rules and 431 user rules
> - 4 probes run against the live boundary, all of them refused as configured
> - 18 passes, 1 error and 6 warnings, so the stack holds everything but its own documentation

### findings
one bullet per issue, leading with the label the sidecar printed

| label | what it found |
|---|---|
| `parse` | a scope that does not parse, so every rule in it is inert |
| `templates` | the plugin's `settings/` is missing or empty, so drift and hygiene read nothing |
| `drift` | an installed copy whose rules differ from its template |
| `verbs` | a path denied for read only, which a write still reaches |
| `scope` | machine detail in a committed file, or a mask the scope cannot honor |
| `hygiene` | duplicate rules, or a template that will not paste |
| `coverage` | a rule with no why in the scope's `.md`, or a mirror claim that has diverged |
| `guard` | nothing protects the policy directories, so this auditor is editable |
| `probe` | a boundary that did not refuse, naming what got through |
| `wrapped` | errors from the wrapped `/operator:permissions` or `/operator:scopes` run |
| `resolution_shape` `resolution_parity` | an older entry whose resolutions do not match its findings |

*example:*
> - **coverage** — 12 rules in `settings.user.json` carry no why in `settings.user.md`
> - **wrapped** — the permissions replay came back with 2 errors, so the gate itself is off
> - **drift** — the installed project copy carries 3 rules its template does not

### resolutions
one checkbox per finding, in the same order, naming the rule and the scope file it belongs in

*example:*
> - [ ] document the 12 undocumented rules in `settings.user.md`, or drop them from the json
> - [ ] run `/operator:permissions` for the detail behind the wrapped count
> - [ ] reconcile the project copy against `settings.project.json`, deciding which is stale

### telemetry
the sidecar's whole output, fenced and unedited, so every claim above can be checked against it

*example:*
> ```text
> === settings.sh sidecar ===
> probes: run
> passes: 18
> errors: 1
> warnings: 6
> ```

## Settings Audit #2: repeat the above format for each deliberate run on the same day
never edit an earlier audit; a stale finding is signal about how long it went unresolved

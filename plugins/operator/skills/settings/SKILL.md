---
name: settings
description: Audit every settings scope for faults that stay silent until they matter, then probe the live boundary to confirm the gate is not dead, or emit the setup commands for one scope instead.
argument-hint: "[--audit] [--static] [--quick] [--local] [--project] [--user] [--managed] [--advanced]"
disable-model-invocation: true
metadata:
  kind: trigger
---
**/operator:settings:** the frontmatter blocks every path except an explicit invocation
- a bare run explains itself, since every real run needs a flag naming which job it wants
- `--audit` grades the merged settings stack for faults that stay silent until they matter
- static checks read the files, and live probes exercise the boundary the files only describe
- a scope flag emits that scope's setup instead, with both paths resolved for either install method
- `--advanced` walks the masked-credential setup, grading the half of it a sidecar can observe
- never edits a settings file; every finding and every command is the user's to apply

## voice

```!
awk 'NR>1 && /^---$/ {p=1; next} p' "${CLAUDE_PLUGIN_ROOT}/output-styles/operator.md"
```

- the block above already ran, and it is the output contract for this response
- it holds for this turn even when the user's active output style is something else
- an empty block means the plugin has no style file; continue, since voice never gates the work

## telemetry

```!
"${CLAUDE_PLUGIN_ROOT}"/skills/settings/settings.sh $ARGUMENTS
echo "sidecar exit: $?"
```

1. read the block above; it already ran with whatever flags the invocation carried
  - NO FLAG → the sidecar printed its own usage; relay it, answer what the user asked, and STOP
  - `--audit`, `--static`, `--quick`, `--strict` → an audit ran; continue to step 2
  - `--local`, `--project`, `--user`, `--managed` → an emit ran; skip to step 4
  - `--advanced` → the credential walkthrough ran; skip to step 5
  - fail (`sidecar exit` > 0) → findings exist; report them rather than rerunning
  - success (`sidecar exit` = 0) → the run is clean; record it in whichever step the flags selected
  - `--audit` takes minutes, since the wrapped sidecars replay their whole corpus; the `probes` and
    `wrapped` telemetry lines carry the seconds each stage spent, so quote them when it ran long

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
    - a scope with no file at all is a setup gap, so name the flag that emits it rather than a fix
    - `guard` firing means the deny protecting this sidecar is absent; restore it before trusting a
      later clean run, since an editable auditor can be made to report clean
    - answer the checklist the sidecar prints, since those rules are the ones no script can judge

4. on an EMIT run, report the commands inline in the sidecar's own order, then STOP

    NEVER run a copy yourself, and never offer to; the commands are the deliverable

    - lead with the scopes whose target is absent, since those copy clean and need no merge
    - a scope reported as populated is a merge decision, so name the rule count already there
    - `managed` needs sudo and lands outside the project, so it is always the reader's call
    - the credential steps are not copies; pass them through as the manual work they are
    - never append an emit run to `[audit_file]`; those lines are absolute paths on one machine

5. on an ADVANCED run, walk the user through the numbered steps, one at a time, then STOP

    NEVER write a token, an env file or a settings rule yourself; the walkthrough is the deliverable

    - open with the state block: what is already in place is not a step to repeat
    - a `gap` line is the finding that matters, since a masked token whose host is missing from
      `allowedDomains` authenticates against a host the sandbox will not resolve
    - `envfile not observable` is the deny rule working, so never report it as a missing file
    - stop at the first step the state block shows unfinished, and ask before moving past it
    - steps 3 and 7 write files this sidecar is denied, so ask the user to confirm rather than check
    - never echo a token value back, even one the user pastes; name the variable instead
    - close by naming `/operator:credentials` as the proof, since it spends the token then reads back

## the shape
> the artifact this skill appends to; the sidecar grades what landed on its next run

# .construct/operator/settings/YYYY-MM-DD.md
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
| `wrapped` | errors from the wrapped `/operator:permissions` or `/operator:scripts` run |
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

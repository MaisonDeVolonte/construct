---
name: test-settings
description: Audit every settings scope for faults that stay silent until they matter, then probe the live boundary to confirm the gate is not dead.
argument-hint: [--static|--quick]
disable-model-invocation: true
metadata:
  kind: trigger
---
**/test-settings:** the frontmatter blocks every path except an explicit invocation
- audits the merged settings stack for faults that are silent until the moment they matter
- static checks read the files: parse, drift, verb symmetry, scope placement, hygiene, guard
- live probes exercise the boundary, since a config can be perfect while the gate is dead
- never edits a settings file; every finding is handed back as the user's to apply

## telemetry

```!
"${CLAUDE_PLUGIN_ROOT}"/skills/test-settings/test-settings.sh
echo "sidecar exit: $?"
```

1. read the block above; it already ran, so there is no command to issue
  - fail (`sidecar exit` > 0) → findings exist; continue to step 2 and report them
  - success (`sidecar exit` = 0) → continue to step 2 and record the clean run
  - `--static` skips the probes and `--quick` skips the wrapped sidecars; both need a tool call,
    since the block above takes no arguments

2. append one entry to `[audit_file]`, in the shape `AGENTS/skills/doc-audits/SKILL.md` defines
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

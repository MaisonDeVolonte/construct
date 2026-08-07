---
name: wayfinders
description: The jsdoc wayfinding header every source file opens with, and where it sits. Validates them.
paths: "**/*.ts, **/*.tsx, **/*.js, **/*.jsx, **/*.mjs, **/*.cjs, **/*.sh"
metadata:
  kind: spec
---
# wayfinder shapes
the rules every wayfinding header holds to, each demonstrated once below.

## scope
- source files, never a `docs/` artifact; `check-comments` owns everything under the header
- eligible extensions are js, jsx, ts, tsx, mjs, cjs and sh, since those are what carry the block
- the block opens on line 1, or on the line under a shebang, with nothing above it
- frontmatter outranks the header, since the harness reads a skill's yaml only from line 1

## form
- `@file`, `@description` and `@see` each appear once, in that order
- a banner of `=` sits above and below the `@file` line, matching its width
- `@file` reads `<filename> - <short, specific title>`, and the filename is the real one
- `@description` is a hyphen delimited list of single clause lines that never wrap
- `@see` is a comma separated list of ALL related internal files
- lines carry a single clause, capped at 100 characters
- lowercase shorthand english, favouring legibility over completeness

## content
- the block says what the file is FOR and where its edges are, never how it works
- a tag that drifted from the file is worse than no tag, so resync it when the file changes
- `@see` earns its place by naming what a reader opens next, not everything the file imports
- group a long `@description` under uppercase headings once it runs past a screenful

## the js/ts form, opening line 1

*example:*
> ```typescript
> /**
>  * ==========================================
>  * @file aggregate.ts - stat formatting layer
>  * ==========================================
>  * @description
>  * - turns raw source rows into ui-ready strings, and caches the result per locale
>  * - fail-soft: a dead source yields a placeholder, never a thrown error
>  * - the only layer allowed to format; everything above it renders what it returns
>  * @see types.ts, apis/source.ts, Widget.tsx
>  */
> ```

## the shell form, opening line 2 under the shebang

*example:*
> ```bash
> #!/bin/bash
> # ========================================
> # @file deploy.sh - production release step
> # ========================================
> # @description
> # - builds, tags and pushes; refuses to run on a dirty tree
> # - the only script that talks to the registry
> # @see Dockerfile, .github/workflows/ci.yml
> ```

## where a skill pair keeps its header

a `SKILL.md` carries no header of its own; its sidecar carries one for the pair, in the shell
form above. the doc keeps frontmatter as its orientation, and the block names both files:

*example:*
> ```markdown
> ---
> name: git-backup
> description: Snapshots history and tree, verifies it, hands over the restore.
> disable-model-invocation: true
> ---
> **/gitgud:backup:** Run ONLY on explicit `/gitgud:backup` command
> ```
> ```bash
> #!/bin/bash
> # ====================================================
> # @file git-backup.sh - full repo snapshot and restore
> # ====================================================
> # @description
> # PAIR
> # - sidecar for `/gitgud:backup` — takes and verifies the snapshot, then hands the restore over
> # - the doc holds the steps; this block holds the map for both halves of the pair
> # @see plugins/gitgud/skills/backup/SKILL.md, tools/check-skills/README.md
> ```

## what a drifted header looks like

*example:*
> ```typescript
> // BAD — @file names a file that was renamed, and @see points at a deleted module
> // BAD — @description explains how the loop works, which the code already shows
> // BAD — a description line wrapping onto the next line instead of splitting by clause
>
> // GOOD — every tag resyncs with the file as it now stands, one clause per line
> ```

```text
VERIFY - not part of the artifact
- RUN `plugins/retardify/skills/wayfinders/wayfinders.sh` after adding or editing a header; pass a path to scope it
- FIX every ERROR, since each one breaks a rule this spec states outright
- STOP on a `secret` finding and ask the user before truncating it; the key needs rotating first
- JUSTIFY or fix every WARN; the sidecar tolerates them, the next reader may not
- ANSWER the checklist it prints, since those rules are the ones no script can judge
- APPEND the run to `audit_file` from the telemetry, in the shape below, when invoked deliberately
- SKIP that append when the run came from the posttooluse hook, which lints rather than audits
```

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

---
name: check-wayfinders
description: The jsdoc wayfinding header every source file opens with, and where it sits. Validates them.
paths: **/*.ts, **/*.tsx, **/*.js, **/*.jsx, **/*.mjs, **/*.cjs, **/*.sh
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
> **@git-backup:** Run ONLY on explicit `@git-backup` command
> ```
> ```bash
> #!/bin/bash
> # ====================================================
> # @file git-backup.sh - full repo snapshot and restore
> # ====================================================
> # @description
> # PAIR
> # - sidecar for `@git-backup` — takes and verifies the snapshot, then hands the restore over
> # - the doc holds the steps; this block holds the map for both halves of the pair
> # @see AGENTS/skills/git-backup/SKILL.md, AGENTS/skills/check-skills/SKILL.md
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
- RUN `AGENTS/skills/check-wayfinders/check-wayfinders.sh` after adding or editing a header; pass a path to scope it
- FIX every ERROR, since each one breaks a rule this spec states outright
- STOP on a `secret` finding and ask the user before truncating it; the key needs rotating first
- JUSTIFY or fix every WARN; the sidecar tolerates them, the next reader may not
- ANSWER the checklist it prints, since those rules are the ones no script can judge
```

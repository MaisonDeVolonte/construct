```javascript
/**
 * ======================================================
 * @file wayfinders.md - jsdoc wayfinding header template
 * ======================================================
 * @description
 * SCOPE
 * - source files, never a `docs/` artifact; the sibling of `comments.md`, which owns the rest
 * - eligible files are js, jsx, ts, tsx, mjs, cjs and sh, since those are what carry the block
 * - everything below the header belongs to `comments.sh`, and nothing here judges it
 * FORM
 * - the block opens on line 1, or line 1 after a shebang, with nothing above it
 * - `@file`, `@description` and `@see` each appear once, in that order
 * - a banner of `=` sits above and below the `@file` line, matching its width
 * - `@file` reads `<filename> - <short, specific title>`, and the filename is the real one
 * - `@description` is a hyphen delimited list of single clause lines that never wrap
 * - `@see` is a comma separated list of ALL related internal files
 * - `lines` carry a single clause, capped at 100 characters
 * - lowercase shorthand english, favouring legibility over completeness
 * CONTENT
 * - the block says what the file is FOR and where its edges are, never how it works
 * - a tag that drifted from the file is worse than no tag, so resync it when the file changes
 * - `@see` earns its place by naming what a reader opens next, not everything the file imports
 * - group a long `@description` under uppercase headings, the way this block does
 * VERIFY
 * - `AGENTS/templates/wayfinders.sh` validates a header against every rule above a script can judge
 * - repo-wide reference integrity has no gate now; `AGENTS/git/gitinsights.sh` only reports it
 * @see AGENTS.md, AGENTS/templates/wayfinders.sh, AGENTS/templates/comments.md, AGENTS/git/gitinsights.sh
 */
```

# wayfinder shapes

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
- RUN `AGENTS/templates/wayfinders.sh` after adding or editing a header; pass a path to scope it
- FIX every ERROR, since each one breaks a rule stated in the header above
- STOP on a `secret` finding and ask the user before truncating it; the key needs rotating first
- JUSTIFY or fix every WARN; the sidecar tolerates them, the next reader may not
- ANSWER the checklist it prints, since those rules are the ones no script can judge
```

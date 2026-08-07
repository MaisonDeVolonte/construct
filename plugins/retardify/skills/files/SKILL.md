---
name: files
description: "Everything about a source file except the logic: its name, its wayfinding header, its module order, and its inline comments. Validates all four."
when_to_use: "Creating or editing any source file, since all four conventions apply to every one. Also when asked to wayfind, comment, rename or reorder imports, when a header has drifted from the file it describes, or when the posttooluse lint reports a finding."
paths: "**/*.ts, **/*.tsx, **/*.js, **/*.jsx, **/*.mjs, **/*.cjs, **/*.sh, **/*.py, **/*.rb, **/*.go, **/*.rs"
metadata:
  kind: spec
---
# file shapes
everything about a source file that is not the logic inside it, in four conventions.
`/retardify:code` owns the logic; this spec owns the frame around it.

## scope
- source files, never a `.operator/` artifact
- naming and module order apply to the js family, which is where those conventions have meaning
- the wayfinding header applies to js, jsx, ts, tsx, mjs, cjs and sh, which carry the block
- comments apply to every language with a full-line marker, which is a wider list than the header
- full-line comments only, since a trailing comment cannot be told from a string reliably

# 1. naming
- `PascalCase.tsx` — ui-rendering components
- `camelCase.tsx` — logic and behavior components
- `camelCase.ts` — utilities and helpers
- `MatchCase.css` — co-located css matches its counterpart
- `kebab-case.css` — general/global css

the sidecar sees whether the casing is one of these shapes. it cannot tell a ui component from a
logic one, so picking the right shape stays a human call.

# 2. wayfinders
the header every eligible source file opens with.

## form
- `@file`, `@description` and `@see` each appear once, in that order
- a banner of `=` sits above and below the `@file` line, matching its width
- `@file` reads `<filename> - <short, specific title>`, and the filename is the real one
- `@description` is a hyphen delimited list of single clause lines that never wrap
- `@see` is a comma separated list of ALL related internal files
- lines carry a single clause, capped at 100 characters
- lowercase shorthand english, favouring legibility over completeness
- the block opens on line 1, or on the line under a shebang, with nothing above it
- frontmatter outranks the header, since the harness reads a skill's yaml only from line 1

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
> ```bash
> #!/bin/bash
> # ====================================================
> # @file backup.sh - full repo snapshot and restore
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

# 3. modules
the import block's order, top to bottom:

- `external` packages (ordered alphabetically)
- `webflow` components (ordered by appearance)
- `internal` @/always/aliased/first-party/code
  - `data/files`
  - `config/schemas`
  - `ui/components`
  - `css` (ordered by cascade specificity)
- `reexported` module bindings
- `exported` bindings, then internal values, then types, then functions

*example:*
> ```typescript
> import { fetchFooCache } from "some-lib";
> import type { FooConfig } from "some-lib";
>
> import { getFoo } from "@/utilities/foo";
> import { FOO_URL } from "@/config/foobar";
> import FooWidget from "@/modules/foo/Widget";
>
> export { helperFn } from "@/utilities/shared";
>
> export const FOO_TAG = "foo-tag";
> export type FooNode = { path: string; type: string };
> ```

the sidecar catches an external import sitting below an aliased one, which inverts the two bands.
the finer grouping inside each band is a human call.

# 4. comments
the rules every inline comment holds to.

## shape
- one clause per line, capped at 100 characters, and never wrapping
- lowercase shorthand english, comma separated, never sentence case
- no trailing period, since a comment is a label and not a sentence
- exactly one space after the marker, so `// like this` and never `//like this`
- a type hint closes a line where it helps, as in `// retry budget — seconds`
- past 2 consecutive lines it stops being a comment and belongs in the wayfinding header
- exempt from all of it: directives, `// SECTION TITLE` headers, banner runs, and url lines

## content
- `why` a thing exists beats `what` it does, unless the code is genuinely hard to follow
- more comments is good, more comments restating the code is noise
- refactoring for legibility beats explaining an unclear line in prose
- commented-out code gets deleted, since git already remembers it

## the default: one clause, lowercase, no period

*example:*
> ```typescript
> // cache key includes the locale, since the same id renders differently per market
> const cacheKey = `${locale}:${id}`;
> ```

## why over what

*example:*
> ```typescript
> // BAD — restates the code, adds nothing a reader could not see
> // increment the counter by one
> counter += 1;
>
> // GOOD — says why this exists, which the code cannot say
> // stripe retries the webhook 3 times, so the counter guards against double-charging
> counter += 1;
> ```

## what to do when it runs long

*example:*
> ```typescript
> // BAD — one clause wearing three, past the cap, wrapping in every editor
> // this function fetches the user, then normalizes their locale against the market table, and caches
>
> // GOOD — one clause per line, each under the cap
> // normalizes locale against the market table before caching
> // a miss here is silent, so the cache key carries the locale too
> ```

## past two lines, it belongs in the wayfinder

*example:*
> ```typescript
> // BAD — four lines of preamble sitting on top of a function
> // this module owns every pricing call
> // it fans out to stripe and to the internal ledger
> // the ledger is authoritative when the two disagree
> // see the pricing rfc for why
>
> // GOOD — that is a file-level description, so it moves into the @description block
> ```

## the exempt cases, which the sidecar skips

*example:*
> ```typescript
> // SECTION HANDLERS
> // eslint-disable-next-line @typescript-eslint/no-explicit-any
> // spec lives at https://example.com/a/very/long/url/that/cannot/be/wrapped/anywhere
> ```

```text
VERIFY - not part of the artifact
- RUN `plugins/retardify/skills/files/files.sh` after writing or editing a source file; pass a path to scope it
- FIX every ERROR, since each one breaks a rule this spec states outright
- STOP on a `secret` finding and ask the user before truncating it; the key needs rotating first
- JUSTIFY or fix every WARN; the sidecar tolerates them, the next reader may not
- ANSWER the checklist it prints, since those rules are the ones no script can judge
- APPEND the run to `audit_file` from the telemetry, in the shape below, when invoked deliberately
- SKIP that append when the run came from the posttooluse hook, which lints rather than audits
```

## the shape
> the artifact this skill appends to; the sidecar grades what landed on its next run

# .operator/files/YYYY-MM-DD.md
one file per day, appended to by every deliberate run:

- the heading reads `## Files Audit #[next_audit]: [timestamp]`, both taken from the telemetry
- an audit captures the tree at a moment in time, so it is never edited after the fact
- carry an unresolved finding forward by restating it, never by editing the older audit
- lines are hyphen bullets holding a single clause, capped at 100 characters
- scrub client names, tokens, and other sensitive detail before it lands in a commit

## Files Audit #1: YYYY-MM-DD HH:MM

### state
the counts as hyphen bullets: files scanned, how many were eligible for a header, errors, warnings

*example:*
> - 41 source files scanned, 38 of them eligible for a wayfinding header
> - 0 errors and 12 warnings, so the tree holds every rule the spec states outright

### findings
one bullet per issue, leading with the label the sidecar printed

| label | what it found |
|---|---|
| `naming` | a filename that is neither PascalCase nor camelCase |
| `no_wayfinder` | an eligible file with no header at all |
| `position` `tag_order` `tag_repeat` | the header is present but malformed |
| `file_tag` | `@file` names a different file than the one it sits in |
| `banner` `wrapped` `description` | the block's own shape rules |
| `see_empty` `see_unresolved` | `@see` is empty, or names a path that resolves to nothing |
| `module_order` | an external import sitting below an `@/` aliased one |
| `spacing` `width` `casing` `period` `clause` | a comment breaking one of the shape rules |
| `block` `block_comment` | a comment run long enough to belong in the wayfinder |
| `commented_code` | commented-out code, which git already remembers |
| `secret` | a credential-shaped string; stop and ask before touching it |

*example:*
> - **clause** — 12 comments chain more than one clause onto a line, worst in doc-plans.sh
> - **see_unresolved** — 3 headers name paths the plugins split renamed
> - **block** — 9 comment runs of 3+ lines, which belong in their file's wayfinder

### resolutions
one checkbox per finding, in the same order, naming the file or the command that closes it

*example:*
> - [ ] split each clause finding onto its own line, worst offender first
> - [ ] resync the 3 stale `@see` lists against the current tree
> - [ ] move each block finding into its file's wayfinder, then re-run the sidecar

### telemetry
the sidecar's whole output, fenced and unedited, so every claim above can be checked against it

*example:*
> ```text
> === files.sh sidecar ===
> scanned: 41 source file(s)
> wayfinder_scope: 38 eligible for a header
> errors: 0
> warnings: 12
> ```

## Files Audit #2: repeat the above format for each deliberate run on the same day
never edit an earlier audit; a stale finding is signal about how long it went unresolved

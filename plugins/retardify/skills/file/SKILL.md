---
name: file
license: MIT
compatibility: requires bash, git
description: file-shape linter run by PostToolUse or via <path> argument (saves audits to .construct/)
argument-hint: "[--help] <path> [--test]"
when_to_use: "editing files, PostToolUse warnings, or when asked to review files"
paths: "**/*.ts, **/*.tsx, **/*.js, **/*.jsx, **/*.mjs, **/*.cjs, **/*.sh, **/*.py, **/*.rb, **/*.go, **/*.rs"
metadata:
  artifact: .construct/retardify/file/
---

**validated file shapes:** keep tokens aimed at logic instead of conventions
- `shape-only` refactors since `/retardify:code` already owns the logic inside it
- `file name` casing is configured and enforced mechanistically
- `wayfinders` improve code orientation and help keep inline comments to a minimum
- `module` organization is standardized for maximum scannability
- `inline comments` are continually synthesized to ensure they're accurate and legible
- `configured` in the skill doc and enforced by the bash sidecar

<details>
<summary>example:</summary>

```typescript
/**
 * =================================================
 * @file widget.ts - generic stateful execution unit
 * =================================================
 * @description
 * - wraps arbitrary payloads into standard lifecycle hooks (init, tick, dispose)
 * - NOTES:
 *   - #1: mutations funnel through internal queue to ensure deterministic ticks
 * @see core/runner.ts
 */

import { fetchFooCache } from "some-library";
import type { FooConfig } from "some-library";

import { getFoo } from "@/utilities/foo";
import type { FooBarShape } from "@/utilities/foobar";
import { FOO_URL, FOO_API_KEY } from "@/config/foobar";
import FooWidget from "@/modules/foo/Widget";
import "@/modules/foo/Widget.css";

export { helperFn } from "@/utilities/shared";

export const FOO_TAG = "foo-tag";
export const FOO_LIST = ["a", "b", "c"];

const FOO_TIMER = 3600;

export type FooNode = { path: string; type: string };

export async function getFoo(): Promise<FooNode[]> { return []; }

// full-line comments only, closed with a type hint when helpful – boolean
// comments that span more than 2 consecutive lines belong in the wayfinder
```

</details>

# Instructions

## Telemetry
```!
if [ -n "$ARGUMENTS" ];
then "${CLAUDE_PLUGIN_ROOT}"/skills/file/file.sh $ARGUMENTS; echo "sidecar exit: $?"
else echo "no path given, so nothing ran; the hook lints every write, so apply the rules below"; fi
```
- `help: requested` → the run was refused before it started; `## Help` below is the whole turn
- this already ran; never re-issue it, and never a bare `file.sh`, which scans the whole tree
- `fail (sidecar exit > 0)` → report the raw terminal error inside a markdown code block
- `success` → take `audit_file`, then follow VERIFY below, fixing every finding

## File Names
> read the file's contents to determine the file type

- `PascalCase.tsx` — ui-rendering components
- `camelCase.tsx` — logic and behavior components
- `camelCase.ts` — utilities and helpers
- `MatchCase.css` — co-located css matches its counterpart
- `kebab-case.css` — general/global css

## Wayfinders
> opens on line 1 for js, jsx, ts, tsx, mjs, and cjs files and opens on line 2 for sh files

- `@file`: `<filename> - <short, specific title>` wrapped in `=` matching its width
- `@description`:
  - a hyphen delimited list of what the file is for and where its edges are
  - one clause per line, capped at 100 characters, and never wrapping
  - use headings to break up descriptions with more than 10 lines
  - #1: use numbered citations for when inline comments run long
- `@see`: a comma separated list of related internal files, sorted by ideal read order
- group, dedupe, and prune wayfinder blocks every time the file changes
- paired .md files are explained in the sidecar's wayfinder block

### JavaScript/TypeScript

```typescript
/**
 * ==========================================
 * @file aggregate.ts - stat formatting layer
 * ==========================================
 * @description
 * - turns raw source rows into ui-ready strings, and caches the result per locale
 * @see types.ts, apis/source.ts, Widget.tsx
 */
```

### Shell

```bash
#!/bin/bash
# =========================================
# @file deploy.sh - production release step
# =========================================
# @description
# - builds, tags and pushes; refuses to run on a dirty tree
# @see Dockerfile, .github/workflows/ci.yml
```

## Modules
> the import block's order, top to bottom:

- `external` packages (ordered alphabetically)
- `webflow` components (ordered by appearance)
- `internal` @/always/aliased/first-party/code
  - `data/files`
  - `config/schemas`
  - `ui/components`
  - `css` (ordered by cascade specificity)
- `reexported` module bindings
- `exported` bindings, then internal values, then types, then functions

## Inline Comments
> applies to every language with a full-line marker

- one clause per line, lowercase, capped at 100 characters, and never wrapping
- `why` a thing exists beats `what` it does, unless the code is genuinely hard to follow
- lots of comments is a sign the code is illegible, consider refactoring or `/retardify:code`
- where possible, add pointers to additional comments in the wayfinder (e.g. `(see #1)`)

```typescript
// GOOD: cache key includes the locale, since the same id renders differently per market
// BAD: combine locale and id to create the cache key
const cacheKey = `${locale}:${id}`;

// GOOD: stripe retries the webhook 3 times, so the counter guards against double-charging
// BAD: increment the counter by one
counter += 1;

// GOOD: mobile network handovers (5G -> Wi-Fi) can deliver Server-Sent Events out of order
// we drop older sequence numbers to prevent UI state regressions (see #1)

// BAD: mobile network handovers (5G -> Wi-Fi) can deliver Server-Sent Events out of order
// we drop older sequence numbers to prevent UI state regressions
// MAX_DRIFT_WINDOW safety hatch ensures we don't permanently freeze updates if the counter resets

if (incomingSeq <= localSeq && (Date.now() - lastSyncedAt) < MAX_DRIFT_WINDOW) { return; }
```

## Verify
- RUN `plugins/retardify/skills/file/file.sh` after writing or editing a source file; a path scopes it
- FIX every ERROR, since each one breaks a rule this spec states outright
- STOP on a `secret` finding and ask the user before truncating it; the key needs rotating first
- JUSTIFY or fix every WARN; the sidecar tolerates them, the next reader may not
- ANSWER the checklist it prints, since those rules are the ones no script can judge
- APPEND the run to `audit_file` from the telemetry, in the shape below, when invoked deliberately
- SKIP that append when the run came from the posttooluse hook, which lints rather than audits
- RE-RUN the sidecar after fixing, so the findings you closed are proven closed

## Artifact Template
> the artifact this skill appends to; the sidecar grades what landed on its next run

```
# .construct/retardify/file/YYYY-MM-DD.md
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
| `width` `casing` `clause` | a comment breaking one of the shape rules |
| `block` `block_comment` | a comment run long enough to belong in the wayfinder |
| `citation_numbering` | the wayfinder's `#1:` notes skip a number or repeat one |
| `citation_unresolved` | a `(see #1)` pointing at a note the wayfinder does not hold |
| `citation_orphan` | a `#1:` note that nothing in the file points at |
| `secret` | a credential-shaped string; stop and ask before touching it |

*example:*
> - **clause** — 12 comments chain more than one clause onto a line, worst in doc-plans.sh
> - **see_unresolved** — 3 headers name paths the plugins split renamed
> - **block** — 9 comment runs of 3+ lines, which belong in their file's wayfinder

### resolutions
one checkbox per finding, in the same order, each carrying something a reader can run
- name the slash command, the script, or the `path` the fix opens, never prose alone
- prose says what to do; a command is what closes the box, so every box holds one

*example:*
> - [ ] `/retardify:file doc-plans.sh` to split each clause finding onto its own line
> - [ ] `/retardify:file` after resyncing the 3 stale `@see` lists against the current tree
> - [ ] `/retardify:code parse.ts` to move each block finding into its file's wayfinder

### telemetry
the sidecar's whole output, fenced and unedited, so every claim above can be checked against it

*example:*
> ```text
> === file.sh sidecar ===
> scanned: 41 source file(s)
> wayfinder_scope: 38 eligible for a header
> errors: 0
> warnings: 12
> ```

## Files Audit #2: repeat the above format for each deliberate run on the same day
never edit an earlier audit; a stale finding is signal about how long it went unresolved
```

## Help
> IF the invocation carries `--help` or `-h`, this section is the whole turn:

```text
SKILL: /plugin:name
DESCRIPTION: <the `description` frontmatter, verbatim>
POSTURE: <the readme index's keyword for this skill>
FLAGS:
- --flag: <what it changes, in the telemetry bullet's own words>
ARGUMENTS:
- <arg>: <what it names>
ARTIFACT: <the `metadata.artifact` path, or none>
OUTPUT: <what lands in the turn: an audit entry, a handover block, an inline report>
SPEC: <this doc's own path>
```

- every field prints, in this order; one with nothing to say prints `none`
- every value is COPIED from the source named beside it, never composed fresh
- ask what they are actually trying to do, and what they have already tried
- name the flag or the sibling skill that fits their answer, then STOP
- run no step, write no file, and never fall through to step 1

## Subagent Style
```!
awk 'NR>1 && /^---$/ {p=1; next} p' "${CLAUDE_PLUGIN_ROOT}/subagent-styles/operator.md"
```

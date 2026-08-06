---
name: check-comments
description: Inline comment shape for every source file: why over how, sparingly, lowercase shorthand. Validates them.
paths: **/*.ts, **/*.tsx, **/*.js, **/*.jsx, **/*.mjs, **/*.cjs, **/*.sh
metadata:
  kind: spec
---
# comment shapes
the rules every inline comment holds to, each demonstrated once below.

## scope
- source files, never a `docs/` artifact; `check-wayfinders` owns the header above them
- full-line comments only, since a trailing comment cannot be told from a string reliably
- exempt from all of it: directives, `// SECTION TITLE` headers, banner runs, and url lines

## shape
- one clause per line, capped at 100 characters, and never wrapping
- lowercase shorthand english, comma separated, never sentence case
- no trailing period, since a comment is a label and not a sentence
- exactly one space after the marker, so `// like this` and never `//like this`
- a type hint closes a line where it helps, as in `// retry budget — seconds`
- past 2 consecutive lines it stops being a comment and belongs in the wayfinding header

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
> // this function fetches the user, then normalizes their locale against the market table, and finally caches
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
- RUN `AGENTS/skills/check-comments/check-comments.sh` after writing or editing a source file; pass a path to scope it
- FIX every ERROR, since each one breaks a rule this spec states outright
- STOP on a `secret` finding and ask the user before truncating it; the key needs rotating first
- JUSTIFY or fix every WARN; the sidecar tolerates them, the next reader may not
- ANSWER the checklist it prints, since those rules are the ones no script can judge
```

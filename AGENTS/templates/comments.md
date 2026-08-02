```javascript
/**
 * =================================================
 * @file comments.md - inline comment shape template
 * =================================================
 * @description
 * SCOPE
 * - source files, never a `docs/` artifact; this is the second template that scans code
 * - full-line comments only, since a trailing comment cannot be told from a string reliably
 * - the wayfinding header is out of scope here, and belongs to `wayfinders.sh` instead
 * SHAPE
 * - `lines` carry a single clause, capped at 100 characters, and never wrap
 * - a comment past 2 consecutive lines belongs in the wayfinding header instead
 * - lowercase shorthand english, comma separated, never sentence case
 * - no trailing period, since a comment is a label and not a sentence
 * - exactly one space after the marker, so `// like this` and never `//like this`
 * - a type hint closes a line where it helps, as in `// retry budget — seconds`
 * CONTENT
 * - `why` a thing exists beats `what` it does, unless the code is genuinely hard to follow
 * - more comments is good, more comments restating the code is noise
 * - refactoring for legibility beats explaining an unclear line in prose
 * - commented-out code gets deleted, since git already remembers it
 * EXEMPT
 * - directives are machine syntax, not prose: eslint-disable, ts-ignore, shellcheck, noqa
 * - `// SECTION TITLE` headers break a long file into parts, and stay uppercase
 * - banner runs of =, - or * decorate a header rather than saying anything
 * - a line carrying a url is exempt from the width cap, since it cannot be wrapped
 * VERIFY
 * - `AGENTS/templates/comments.sh` validates a source file against every rule above a script can judge
 * @see AGENTS.md, AGENTS/templates/comments.sh, AGENTS/templates/wayfinders.md, AGENTS/hooks/posttooluse.sh
 */
```

# comment shapes

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
- RUN `AGENTS/templates/comments.sh` after writing or editing a source file; pass a path to scope it
- FIX every ERROR, since each one breaks a rule stated in the header above
- STOP on a `secret` finding and ask the user before truncating it; the key needs rotating first
- JUSTIFY or fix every WARN; the sidecar tolerates them, the next reader may not
- ANSWER the checklist it prints, since those rules are the ones no script can judge
```

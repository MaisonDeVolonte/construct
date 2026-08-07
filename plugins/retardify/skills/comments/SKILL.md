---
name: comments
description: "Inline comment shape for every source file: why over how, sparingly, lowercase shorthand. Validates them."
paths: "**/*.ts, **/*.tsx, **/*.js, **/*.jsx, **/*.mjs, **/*.cjs, **/*.sh"
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
- RUN `plugins/retardify/skills/comments/comments.sh` after writing or editing a source file; pass a path to scope it
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

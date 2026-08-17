---
name: context
model: opus
effort: max
license: MIT
compatibility: requires bash, jq, git
description: prove what literally reached this session's context, read from its transcript (saves report to .construct/)
argument-hint: "[--help] [--quick] [--strict] [--keep]"
disable-model-invocation: true
disallowed-tools: WebFetch, WebSearch
metadata:
  kind: trigger
  artifact: .construct/operator/context/
---
**provable context:** ensure the payload each hook emitted is the payload that actually landed
- answers one question: did what a hook declared reach context, byte for byte
- a hook can run, exit 0 and print perfectly, and still inject nothing once it passes the cap
- reads the session's own transcript, so a drop is measured rather than inferred from a replay

# Instructions

## Telemetry
```!
"${CLAUDE_PLUGIN_ROOT}"/skills/context/context.sh $ARGUMENTS
echo "sidecar exit: $?"
```
- `help: requested` → the run was refused before it started; `## Help` below is the whole turn
- it already ran, so there is no command to issue
- fail (`sidecar exit` > 0) → a payload was lost; report it and continue to step 1
- success (`sidecar exit` = 0) → report what landed and continue to step 1
- `--quick` reports inline and writes nothing, `--strict` promotes warnings, `--keep` holds scratch

1. read the three tiers differently, because each is proven by a different thing
  - the hook boundary is ground truth: `declared` is what the script wrote to stdout, and
    `landed` is the string the harness recorded putting into context. `dropped` means those two
    disagree, which is the defect this skill exists to catch
  - `headroom` is measured on `stdout`, never on `declared`, since the cap judges the escaped
    json and a budget set on the pre-escape body is a guess about how much escaping will cost
  - the harness table is context nothing in this repo can budget, so read it as a floor on
    what a session spends before a single file is read
  - `tokens` is the api's own count and outranks every character figure above it

2. report the boundary table inline, and lead with the verdict column rather than the sizes
  - a `dropped` row is the whole finding; name the script, the event and the chars lost
  - a `budget` finding is a prediction, not a loss: say what would drop when the input grows
  - `uncapped` names an injector with no budget line at all, which is the shape that fails silently
  - `resume` means the batch replayed, so every session-start payload is in context more than once

3. IF `--quick`, STOP after the inline report

    - the flag exists to answer "what is in my context" in one turn, so nothing is written
    - `audit_file: none` in the telemetry is the confirmation, not an omission to repair

4. append one entry to `[audit_file]`, in the shape defined under `## the shape` below
  - the heading reads `## Context Audit #[next_audit]: [timestamp]`, both from the telemetry
  - `state` is what the run measured, as hyphen bullets, one clause each
  - `findings` lead with the kind the sidecar printed, one bullet each, naming the script it hit
  - `resolutions` are checkboxes, one per finding, in the same order
  - `telemetry` is the sidecar's whole output, fenced and unedited, pasted last
  - CREATE the file first if it does not exist, with `# <audit_file>` as its only line

5. STOP

    NEVER edit a hook to fix a finding, and never offer to; the audit is the deliverable

    - a budget change moves what every future session sees, which is the user's call to make
    - never paste a landed payload into the report; the sizes are the finding, the bodies are noise
    - a session id the sidecar could not resolve is itself a finding, not a reason to replay hooks

## the shape
> the artifact this skill appends to; the sidecar grades what landed on its next run

# .construct/operator/context/YYYY-MM-DD.md
one file per day, appended to by every deliberate run:

- the heading reads `## Context Audit #[next_audit]: [timestamp]`, both from the telemetry
- an audit captures one session at a moment in time, so it is never edited after the fact
- carry an unresolved finding forward by restating it, never by editing the older audit
- lines are hyphen bullets holding a single clause, capped at 100 characters
- scrub client names, tokens, and other sensitive detail before it lands in a commit

## Context Audit #1: YYYY-MM-DD HH:MM

### state
the counts as hyphen bullets: payloads landed, chars injected, harness chars, tokens, errors, warnings

*example:*
> - 4 session-start payloads declared, 4 landed whole, 0 dropped at the boundary
> - 19,438 chars injected by hooks against 8,950 the harness attached on its own
> - 72,803 tokens in context at the last turn, of which 71,969 were served from cache

### findings
one bullet per issue, leading with the kind the sidecar printed

| kind | what it found |
|---|---|
| `dropped` | a hook declared a payload and none of it reached context |
| `capped` | a payload's stdout is at or past the cap, so the rest became a preview |
| `margin` | a payload landed with less than 500 chars of room under the cap |
| `budget` | the injector's own budget, spent in full, would escape past the cap |
| `uncapped` | a session-start injector with no budget line anywhere in its source |
| `resume` | more than one session-start batch, so every payload landed again |
| `hook_error` | a hook run injected an error instead of the payload it was written to send |
| `no_transcript` | the session id did not resolve, so nothing below was measured |

*example:*
> - **budget** — `inject-readme.sh` at a full 9,500 chars escapes to 9,772, 228 under the cap
> - **uncapped** — `inject-support.sh` has no budget line, so a longer install path truncates it
> - **resume** — 3 session-start batches, so the readme is in context 3 times over

### resolutions
one checkbox per finding, in the same order, naming the file and the value it belongs in

*example:*
> - [ ] lower `PAYLOAD_BUDGET` in `inject-readme.sh` to 9,000, since escaping costs ~3%
> - [ ] add a `PAYLOAD_BUDGET` to `inject-support.sh`, the only injector with no cap
> - [ ] run `/operator:context --quick` after a resume, since the counts double per batch

### telemetry
the sidecar's whole output, fenced and unedited, so every claim above can be checked against it

*example:*
> ```text
> === context.sh audit ===
> cap: 10000 chars per hook payload, then a 2048-byte preview instead
> tokens: 72803 in context at the last turn — 71969 cached, 832 new, 2 fresh
> injected: 19438 chars over 4 landed payload(s)
> harness: 8950 chars over 4 attachment kind(s)
> errors: 0
> warnings: 3
> ```

- `injected` counts only what landed, so it falls below the declared total whenever one drops
- `harness` is the floor a session pays before any hook or any file read is counted

## Context Audit #2: repeat the above format for each deliberate run on the same day
never edit an earlier audit; a stale finding is signal about how long it went unresolved

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

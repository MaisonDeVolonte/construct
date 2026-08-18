---
name: hooks
model: opus
effort: max
license: MIT
compatibility: requires bash, jq, git
description: prove every hook loads, resolves and fires, before a silent scope drop hides one (saves report to .construct/)
argument-hint: "[--help] [--quick] [--strict] [--keep] <path> [--test]"
disable-model-invocation: true
disallowed-tools: WebFetch, WebSearch
metadata:
  artifact: .construct/operator/hooks/
---
**provable hooks:** ensure every hook this machine registers is one the harness will actually load
- answers one question: is a hook block loadable, resolvable and proven to have run
- one matcher of the wrong type makes the harness skip that whole file, every event inside it
- an interactive session dialogs that; `claude -p` drops the file and says nothing at all

# Instructions

## Telemetry
```!
"${CLAUDE_PLUGIN_ROOT}"/skills/hooks/hooks.sh $ARGUMENTS
echo "sidecar exit: $?"
```
- `help: requested` → the run was refused before it started; `## Help` below is the whole turn
- it already ran, so there is no command to issue
- fail (`sidecar exit` > 0) → a scope will not load; report it and continue to step 1
- success (`sidecar exit` = 0) → report what registered and continue to step 1
- `--quick` reports inline and writes nothing, `--strict` promotes warnings, `--keep` holds scratch

1. read the three tiers differently, because each is proven by a different thing
  - registration is json the harness has to accept: a `matcher` finding is the file being
    discarded whole, so every other hook in it dies with the one that is wrong
  - resolution is the filesystem: a registered command whose file is gone never runs, and
    a rename that misses `hooks.json` unregisters an action without touching it
  - liveness is the session transcript, the only record that a hook actually ran here
  - registration passing while liveness is empty is the exact shape of a silently skipped file

2. report the registration table inline, and lead with the findings rather than the counts
  - a `matcher` finding is the whole report; name the file, the event and the index
  - `orphan` and `missing` are opposites: one action nobody registers, one registration with no action
  - `no_transcript` means liveness was not measured, which is normal in ci and not a defect

3. IF `--quick`, STOP after the inline report

    - the flag exists to answer "will my hooks load" in one turn, so nothing is written
    - `audit_file: none` in the telemetry is the confirmation, not an omission to repair

4. append one entry to `[audit_file]`, in the shape defined under `## the shape` below
  - the heading reads `## Hooks Audit #[next_audit]: [timestamp]`, both from the telemetry
  - `state` is what the run measured, as hyphen bullets, one clause each
  - `findings` lead with the kind the sidecar printed, one bullet each, naming the file it hit
  - `resolutions` are checkboxes, one per finding, in the same order
  - `telemetry` is the sidecar's whole output, fenced and unedited, pasted last
  - CREATE the file first if it does not exist, with `# <audit_file>` as its only line

5. STOP

    NEVER edit a hook or a settings scope to fix a finding, and never offer to; the audit is the deliverable

    - a matcher fix changes what every future session loads, which is the user's call to make
    - never paste a settings scope into the report; the findings are the deliverable, the file is noise
    - a version the sidecar could not probe is itself a finding, not a reason to guess one

## the shape
> the artifact this skill appends to; the sidecar grades what registered on its next run

# .construct/operator/hooks/YYYY-MM-DD.md
one file per day, appended to by every deliberate run:

- the heading reads `## Hooks Audit #[next_audit]: [timestamp]`, both from the telemetry
- an audit captures one machine at a moment in time, so it is never edited after the fact
- carry an unresolved finding forward by restating it, never by editing the older audit
- lines are hyphen bullets holding a single clause, capped at 100 characters
- scrub client names, tokens, and other sensitive detail before it lands in a commit

## Hooks Audit #1: YYYY-MM-DD HH:MM

### state
the counts as hyphen bullets: scopes read, groups registered, actions resolved, hooks fired, errors, warnings

*example:*
> - 6 files carry a hooks block, all 6 parse and all 6 load
> - 11 actions registered, 11 resolved on disk, 0 orphans under hooks/
> - 5 of 5 registered events fired this session, proven from the transcript

### findings
one bullet per issue, leading with the kind the sidecar printed

| kind | what it found |
|---|---|
| `matcher` | a matcher is not a string, so the harness skips that entire file |
| `malformed` | a hook group is not an object, so the file is rejected the same way |
| `unparseable` | the file is not valid json, so nothing in it is read |
| `missing` | a registered command names a file that does not exist |
| `empty_command` | a hook entry registers no command at all |
| `regex` | a matcher is a string the regex engine rejects, which a newer harness may refuse |
| `orphan` | a `.sh` under `hooks/` that no `hooks.json` registers |
| `not_executable` | a registered action exists but carries no execute bit |
| `ask_verdict` | a blocker emits `ask`, which bypassPermissions may auto-approve |
| `empty` | a hook group registers zero hooks, so its matcher guards nothing |
| `type` | a hook entry is not of type `command`, so it runs nothing |
| `unresolved` | a command names no path this can resolve, so it went ungraded |
| `silent` | the transcript records no hook run at all, which is how a skipped file reads |
| `no_transcript` | no session id resolved, so liveness went unmeasured |

*example:*
> - **matcher** — `settings.json:PreToolUse.0` is an object, so all 4 events in that file are skipped
> - **orphan** — `block-outside-moves.sh` sits under hooks/ and no hooks.json registers it
> - **silent** — no hook run recorded, which is the shape a discarded scope leaves behind

### resolutions
one checkbox per finding, in the same order, naming the file and the value it belongs in

*example:*
> - [ ] change `matcher` in `.claude/settings.json` to a string, or delete the key to match all
> - [ ] register `block-outside-moves.sh` in `hooks.json`, or delete it
> - [ ] rerun after a restart, since hooks load at startup and a mid-session edit never applies

### telemetry
the sidecar's whole output, fenced and unedited, so every claim above can be checked against it

*example:*
> ```text
> === hooks.sh audit ===
> version: 2.1.221 (Claude Code)
> scopes: 6 file(s) carrying a hooks block or a settings template
> groups: 5 hook group(s) registered across them
> actions: 11 command path(s) resolved, 0 orphan(s) under hooks/
> blockers: 3 action(s) emitting a permissionDecision
> errors: 0
> warnings: 0
> ```

- `scopes` counts files read, so a scope that does not exist on this machine is never counted
- `blockers` counts actions emitting a verdict, which is the population `ask_verdict` grades

## Hooks Audit #2: repeat the above format for each deliberate run on the same day
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

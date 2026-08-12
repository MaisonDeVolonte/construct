---
name: audit
model: opus
effort: max
license: MIT
compatibility: requires bash, jq, git, curl
description: run every operator lens and merge them into one report (saves report to .construct/)
argument-hint: "[--help] [--confirm]"
disable-model-invocation: true
disallowed-tools: Edit, Write
metadata:
  kind: trigger
  artifact: .construct/operator/audit/
---
**built-in security suite:** lets you reach for a comprehensive audit of your entire claude code setup
- runs settings, permissions, scripts, credentials and issues, then keeps each output whole
- recomputes no verdict; each lens grades itself and this collects what they returned
- correlates across lenses, which no single lens can do from inside itself
- takes no lens flag, since one lens belongs to its own skill and its own artifact
- prices the run against the sidecars it would replay, and asks before spending any of it
- costs minutes, and names the seconds each lens spent so a long stage reads as work

# Instructions

## Telemetry
```!
"${CLAUDE_PLUGIN_ROOT}"/skills/audit/audit.sh $ARGUMENTS
echo "sidecar exit: $?"
```
- `help: requested` → the run was refused before it started; `## Help` below is the whole turn
- `confirm: required` → nothing ran; `## Confirm` below is the whole turn
- it already ran with whatever flags the invocation carried
- `--confirm` → all five lenses ran; continue to step 1
- `fatal: unknown flag` → a lens flag was tried; name the sibling skill that owns it, and STOP
- fail (`sidecar exit` > 0) → findings exist; report them rather than rerunning
- success (`sidecar exit` = 0) → every lens ran clean; record it anyway, since coverage is the claim
- NEVER rerun a lens on its own to check this one; the verbatim block below already holds its output

1. append one entry to `[audit_file]`, in the shape defined under `## the shape` below
    - the heading reads `## Suite Audit #[next_audit]: [timestamp]`, both from the telemetry
    - `state` is the counts as hyphen bullets: lenses run, seconds spent, errors and warnings
    - `findings` name the lens they came from, as `- **Lens/Label** — what it hit`
    - `resolutions` are checkboxes, one per finding, naming the command that resolves it
    - `telemetry` is `#### <lens>` then that lens's whole block, fenced and unedited, all five
    - CREATE the file first if it does not exist, with `# <audit_file>` as its only line

2. report the suite inline, then STOP

    NEVER edit a settings file, a script or a rule to fix a finding; the report is the deliverable

    - OPEN by naming what ran, the seconds the `lenses` line reports, and `[audit_file]` as the copy
    - an `ungraded` lens outranks every count, since that lens answered nothing at all
    - a lens verdict belongs to that lens; carry it across unchanged rather than regrading it
    - a `settings/Verbs` error is latent until an allow reaches the path, which the permissions
      block in this same report is what proves; read the two together and say which it is
    - a `scripts/Unguarded Internal` finding names a command a rule never judged, so pair it with
      the permissions replay before calling it a gap in the rules
    - a `credentials` unruled row and a `settings/Scope` finding are often the same missing rule
    - `issues` findings are upstream movement, so they date the rest of the report rather than fault it
    - NEVER apply the known-issues banner the issues lens drafts; name it as a resolution instead
    - answer the checklist the sidecar prints, since those rules are the ones no script can judge

## the shape
> the artifact this skill appends to; the sidecar grades what landed on its next run

# .construct/operator/audit/YYYY-MM-DD.md
one file per day, appended to by every deliberate run:

- the heading reads `## Suite Audit #[next_audit]: [timestamp]`, both from the telemetry
- an audit captures the stack at a moment in time, so it is never edited after the fact
- carry an unresolved finding forward by restating it, never by editing the older audit
- lines are hyphen bullets holding a single clause, capped at 100 characters
- scrub client names, tokens, and other sensitive detail before it lands in a commit

## Suite Audit #1: YYYY-MM-DD HH:MM

### state
the counts as hyphen bullets: lenses run, seconds spent, passes, errors, warnings

*example:*
> - all 5 lenses ran in 274s, so this report answers for the whole stack
> - scripts spent 268s of that, replaying every command it extracted
> - 4 passes, 2 errors and 7 warnings, so two lenses came back with work

### findings
one bullet per issue, naming the lens it came from as `Lens/Label`

| label | what it found |
|---|---|
| `Suite/...` | a lens that never ran, or ran without printing a verdict |
| `Settings/...` | a fault in the settings files: parse, drift, verbs, scope, hygiene, coverage, guard |
| `Permissions/...` | a corpus command the real hook did not refuse, or merged-rule drift |
| `Scripts/...` | a command inside a script that no rule judges |
| `Credentials/...` | a credential-shaped variable that is neither masked, unset nor ruled |
| `Issues/...` | upstream movement on an issue this repo cites |

*example:*
> - **Scripts/Unguarded Internal** — 11 commands in gitgud sidecars match no rule
> - **Settings/Coverage** — 18 rules in `settings.user.json` carry no why in `settings.user.md`
> - **Credentials/Unruled** — CLOUDSDK_PROXY_PASSWORD is named like a credential and unruled

### resolutions
one checkbox per finding, in the same order, naming the command that resolves it

*example:*
> - [ ] add a deny or an ask for the 11 unguarded commands in `settings.project.json`
> - [ ] document the 18 undocumented rules in `settings.user.md`, or drop them from the json
> - [ ] rule CLOUDSDK_PROXY_PASSWORD in `sandbox.credentials.envVars`, then `/operator:credentials`

### telemetry
`#### <lens>` then that lens's whole block, fenced and unedited, all five every time

*example:*
> #### settings
> ```text
> === settings.sh sidecar ===
> passes: 21
> errors: 1
> warnings: 6
> ```

## Suite Audit #2: repeat the above format for each deliberate run on the same day
never edit an earlier audit; a stale finding is signal about how long it went unresolved

## Confirm
> IF the telemetry reads `confirm: required`, this section is the whole turn:

```text
SKILL: /plugin:name
SCOPE: <what one run covers, from the preamble bullets>
COST: <the `estimate` line, verbatim>
ARTIFACT: <the `metadata.artifact` path>
RERUN: /plugin:name --confirm
```

- state the cost BEFORE asking, then ask once and STOP
- run no step, write no file, and never fall through to step 1
- a fast estimate still asks, since the user decides what is worth a turn
- on a yes, hand back the RERUN line and say the run holds the turn until it returns
- when a confirmed run returns, lead with what happened, the seconds it took, and the artifact path
- an earlier confirmation never covers a later run

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

## Output Style
```!
awk 'NR>1 && /^---$/ {p=1; next} p' "${CLAUDE_PLUGIN_ROOT}/output-styles/operator.md"
```

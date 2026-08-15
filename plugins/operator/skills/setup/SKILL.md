---
name: setup
model: opus
effort: max
license: MIT
compatibility: requires bash, jq, git, curl
description: step by step setup wizard that takes you from install to fully configured (saves roadmap to .construct/)
argument-hint: "[--help] [--roadmap] [--audit] [--confirm]"
disable-model-invocation: true
disallowed-tools: Edit, Write
metadata:
  kind: trigger
  artifact: .construct/operator/setup/
---
**end-to-end install wizard:** takes the guesswork out of securing your agentic workspace
- probes your machine's state and maps out a detailed roadmap all the way through
- interactive questionnaire helps you decide which sandbox config is right for you
- ends with a clean `--audit` handoff that makes sure everything is fully secure
  - runs settings, permissions, scripts, credentials and upstream, then keeps each output whole
  - recomputes no verdict; each lens grades itself and this collects what they returned
  - correlates across lenses, which no single lens can do from inside itself
  - takes no lens flag, since one lens belongs to its own skill and its own artifact
  - prices the run against the sidecars it would replay, and asks before spending any of it
  - costs minutes, and names the seconds each lens spent so a long stage reads as work

# Instructions

## Telemetry
```!
"${CLAUDE_PLUGIN_ROOT}"/skills/setup/setup.sh $ARGUMENTS
echo "sidecar exit: $?"
```
- `help: requested` → the run was refused before it started; `## Help` below is the whole turn
- `confirm: required` → the suite was priced and nothing ran; `## Confirm` below is the whole turn
- it already ran with whatever flags the invocation carried
- NO FLAG → the machine was probed; continue to step 1
- `--roadmap` → a reprint ran and nothing was probed; skip to step 3
- `--audit --confirm` → the whole suite ran, in this sidecar's audit mode; skip to step 4
- fail (`sidecar exit` > 0) → a preflight refused; report what it named rather than rerunning
- success (`sidecar exit` = 0) → the run is clean; record it in whichever step the flags selected
- the `todo` line carries how many steps are still outstanding, so quote it when it is not zero

1. append one entry to `[roadmap_file]`, in the shape defined under `## the shape` below
    - the heading reads `## Setup Roadmap #[next_roadmap]: [timestamp]`, both from the telemetry
    - `state` is the state block as hyphen bullets: deps, route, style, scopes, sandbox, credentials
    - `route` names the tier the reader picked, and the two answers that picked it
    - `steps` are checkboxes, one per numbered step, checked only where the sidecar printed `[done]`
    - `telemetry` is the sidecar's whole output, fenced and pasted last, home paths masked
    - CREATE the file first if it does not exist, with `# <roadmap_file>` as its only line

2. walk the reader through the outstanding steps, ONE at a time, then STOP

    NEVER run an install, paste a settings block, or write a settings file; the roadmap is the deliverable

    - open with the state block, since a step already in place is not a step to repeat
    - ask q1 and q2 before naming any tier, because two answers are what pick one branch
    - stop at the first step reading `[todo]`, and ask before moving past it
    - a `[done]` step was seen by a probe, so name the probe rather than claiming the work
    - `deps` outranks every step below it, since jq is what every later probe reads with
    - install is the reader's to run, since a skill cannot install the plugin that carries it
    - the managed scope needs sudo and lands outside the project, so it is always their call
    - close by naming step 7, since `--audit` is what proves the six steps above it

3. on a ROADMAP run, report the saved roadmap inline, then STOP

    NEVER re-probe to check it; a reprint is a reprint, and the state it holds is dated

    - lead with the file's date, since a stale roadmap describes a machine that has since moved
    - name any step still unchecked, and offer the bare run that re-probes them

4. on an AUDIT run, append one entry to `[audit_file]`, then report the suite inline, then STOP

    NEVER edit a settings file, a script or a rule to fix a finding; the report is the deliverable

    - the heading reads `## Suite Audit #[next_audit]: [timestamp]`, both from the telemetry
    - OPEN by naming what ran, the seconds the `lenses` line reports, and `[audit_file]` as the copy
    - an `ungraded` lens outranks every count, since that lens answered nothing at all
    - a lens verdict belongs to that lens; carry it across unchanged rather than regrading it
    - a `settings/Verbs` error is latent until an allow reaches the path, which the permissions
      block in this same report is what proves; read the two together and say which it is
    - a `credentials` unruled row and a `settings/Scope` finding are often the same missing rule
    - `issues` findings are upstream movement, so they date the rest of the report rather than fault it
    - NEVER apply the known-issues banner the issues lens drafts; name it as a resolution instead
    - answer the checklist the sidecar prints, since those rules are the ones no script can judge

## the shape
> two artifacts under one root; the roadmap records position, the audit records coverage

# .construct/operator/setup/roadmap/YYYY-MM-DD.md
one file per day, appended to by every wizard run:

- the heading reads `## Setup Roadmap #[next_roadmap]: [timestamp]`, both from the telemetry
- a roadmap captures where the reader stood at a moment, so it is never edited after the fact
- carry an unfinished step forward by restating it, never by checking a box in an older entry
- lines are hyphen bullets holding a single clause, capped at 100 characters
- scrub home paths, client names and tokens before it lands in a commit

## Setup Roadmap #1: YYYY-MM-DD HH:MM

### state
the state block as hyphen bullets: deps, route, style, scopes, sandbox, credentials, artifacts

*example:*
> - jq, git and curl all present, so every probe below ran
> - clone route, symlinked from ~/Developer/construct
> - 4 scopes carry a file, and the user scope holds the only sandbox block

### route
the tier the reader picked, and the two answers that picked it

*example:*
> - q1 answered "only me", so the personal scope is the target
> - q2 answered "yes", so tier 5 follows tier 3 rather than closing the run

### steps
one checkbox per numbered step, checked only where the sidecar printed `[done]`

*example:*
> - [x] deps: jq 1.8.1, git and curl on PATH
> - [ ] sandbox: paste the emitted block, restart the editor, then check `/sandbox`
> - [ ] prove: `/operator:setup --audit --confirm`

### telemetry
the sidecar's whole output, fenced, with every home path masked before it lands

- masking is the one edit allowed here, since the state block prints absolute paths
- the mask keeps this file committable, and the scrub rule above is what demands it

*example:*
> ```text
> === setup.sh sidecar ===
> mode       wizard
> todo: 1
> ```

# .construct/operator/setup/audit/YYYY-MM-DD.md
one file per day, appended to by every confirmed `--audit` run:

- the heading reads `## Suite Audit #[next_audit]: [timestamp]`, both from the telemetry
- an audit captures the stack at a moment in time, so it is never edited after the fact
- carry an unresolved finding forward by restating it, never by editing the older audit
- `state` is the counts as hyphen bullets: lenses run, seconds spent, errors and warnings
- `findings` name the lens they came from, as `- **Lens/Label** — what it hit`
- `resolutions` are checkboxes, one per finding, in the same order, naming the command that resolves it
- `telemetry` is `#### <lens>` then that lens's whole block, fenced and unedited, all five every time

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
> - [ ] add a deny or an ask for the 11 unguarded commands in `settings.project.json`

## Suite Audit #2: repeat the above format for each deliberate run on the same day
never edit an earlier entry; a stale finding is signal about how long it went unresolved

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

## Subagent Style
```!
awk 'NR>1 && /^---$/ {p=1; next} p' "${CLAUDE_PLUGIN_ROOT}/subagent-styles/operator.md"
```

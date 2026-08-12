---
name: audit
model: opus
effort: high
license: MIT
compatibility: requires bash, jq, git
description: read the whole repo for composition, pairing, manifest agreement and freshness (saves report to .construct/)
argument-hint: "[--help] [--confirm]"
disable-model-invocation: true
disallowed-tools: Edit
metadata:
  kind: trigger
  artifact: .construct/gitgud/audit/
---
**what a fresh clone would load:** drift you cannot see from inside your own tree
- read-only: it counts and compares, and never mutates a tracked file
- checks composition, skill pairing, manifest agreement and artifact freshness
- prices the run against the tracked files it would walk, and asks before spending any of it
- outputs a numbered list, each finding with the command that shows the detail

# Instructions

## Telemetry
```!
"${CLAUDE_PLUGIN_ROOT}"/skills/audit/audit.sh $ARGUMENTS
echo "sidecar exit: $?"
```
- `help: requested` → the run was refused before it started; `## Help` below is the whole turn
- `confirm: required` → nothing ran; `## Confirm` below is the whole turn
- it already ran, so there is no command to issue
- fail (`sidecar exit` > 0) → abort and report: "<raw terminal error>"
- success (`sidecar exit` = 0) → continue to step 1

1. grade each section, and report ONLY what is off; a healthy section earns one line, not a table
  - `composition` → a plugin with 0 skills is a load failure, never an empty plugin
  - `pairing` → any non-zero orphan count is a broken trigger or dead code, never a style nit
  - `manifests` → a version of `unset` pins nothing, so every commit reads as a new release
  - `manifests` → catalog entries fewer than plugins means an installed bundle cannot resolve
  - `shared` → any drift is an ERROR, since duplication only holds while the copies agree
  - `shared` → a copy count below the plugin count means a plugin cannot reach the library at all
  - `artifacts` → a directory whose latest file predates the last week means its writer stalled

2. output a numbered condition list, worst first
  - OPEN by naming what ran, the seconds it took, and the artifact path holding the copy
  - each entry names the finding, why it matters, and the one command that shows the detail
  - say plainly when a section is clean rather than padding the list to look thorough
  - never propose a fix the telemetry does not support; an unread directory is not a stale one

3. append one entry to `[audit_file]`, in the shape defined under `## the shape` below
  - the heading reads `## Git Audit #[next_audit]: [timestamp]`, both from the `archive` section
  - `state` is what the run measured, as hyphen bullets, one clause each
  - `findings` lead with the label this doc assigns, one bullet each, naming what it hit
  - `resolutions` are checkboxes, one per finding, in the same order
  - `telemetry` is the sidecar's whole output, fenced and unedited, pasted last
  - CREATE the file first if it does not exist, with `# <audit_file>` as its only line

4. close with the two reads this sidecar deliberately does not perform
  - `bash plugins/gitgud/shared/triage.sh` for branch, remote and team state
  - `bash .claude/skills/validate-skills/validate-skills.sh` for the graded shape errors behind `pairing`

## the shape
> the artifact this skill appends to; the sidecar grades what landed on its next run

# .construct/gitgud/audit/YYYY-MM-DD.md
one file per day, appended to by every deliberate run:

- the heading reads `## Git Audit #[next_audit]: [timestamp]`, both from the telemetry
- an audit captures the repo at a moment in time, so it is never edited after the fact
- carry an unresolved finding forward by restating it, never by editing the older audit
- lines are hyphen bullets holding a single clause, capped at 100 characters
- scrub client names, tokens, and other sensitive detail before it lands in a commit

## Git Audit #1: YYYY-MM-DD HH:MM

### state
the counts as hyphen bullets: what the tree is made of, and what each section measured

*example:*
> - 78 tracked files across 3 plugins, carrying 19 skills and 6 hooks
> - 19 skill docs, 0 missing a sidecar and 0 sidecars missing a doc
> - 3 secrets.sh copies, all byte identical, against 3 plugins

### findings
one bullet per issue, leading with the label this doc assigns

| label | what it found |
|---|---|
| `Load Failure` | a plugin reporting 0 skills, which is a load failure and not an empty plugin |
| `Orphan Pair` | a doc with no sidecar, or a sidecar with no doc |
| `Unpinned Version` | a manifest version of `unset`, so every commit reads as a new release |
| `Catalog Gap` | fewer catalog entries than plugins, so an installed bundle cannot resolve |
| `Shared Drift` | the `secrets.sh` copies disagree, which duplication only survives while they match |
| `Missing Copy` | fewer copies than plugins, so a plugin cannot reach the library at all |
| `Stale Artifact` | a kind whose newest file is old, meaning its writer stopped being run |

*example:*
> - **Shared Drift** — 2 versions across 3 secrets.sh copies; retardify holds the stale one
> - **Stale Artifact** — `.construct/operator/credentials/` has not been written since 2026-08-01
> - **Unpinned Version** — gitgud and retardify both carry `version: unset`

### resolutions
one checkbox per finding, in the same order, naming the command that closes it

*example:*
> - [ ] `bash .claude/skills/export-readme/export-readme.sh --apply secrets` to re-land the copies from the readme
> - [ ] `/operator:credentials` to refresh the kind, or accept in writing that it is dormant
> - [ ] set a real `version` in both manifests, then `claude plugin tag` each one

### telemetry
the sidecar's whole output, fenced and unedited, so every claim above can be checked against it

*example:*
> ```text
> --- pairing ---
> skill_docs: 19
> docs_missing_sidecar: 0
> --- archive ---
> audit_file: .construct/gitgud/audit/YYYY-MM-DD.md
> next_audit: 1
> ```

## Git Audit #2: repeat the above format for each deliberate run on the same day
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

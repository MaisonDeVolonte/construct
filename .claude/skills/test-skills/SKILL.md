---
name: test-skills
model: opus
effort: high
license: MIT
compatibility: requires bash, git, perl
description: runs every skill's sidecar at a shallow depth and proves each still answers (saves report to .construct/)
argument-hint: "[--help] [--quick] [--strict] <path> [--test]"
when_to_use: "Before a release, after a rename or a moved shared file, or when a skill fails to load and you need to know which ones still run. Also when adding a skill, to confirm it answers the --test contract."
disable-model-invocation: true
metadata:
  artifact: .construct/maintainer/test-skills/
---

# Instructions

## Telemetry
```!
.claude/skills/test-skills/test-skills.sh "$ARGUMENTS"
echo "sidecar exit: $?"
```
- it already ran, so there is no command to issue
- no argument runs every sidecar under `plugins/*/skills/` and `.claude/skills/`; a path scopes it
- `scanned: N sidecar(s)` → what the run covered, which is one sidecar per skill directory
- `adopted: N without a --test case` → skills still outside the contract, and each one is a WARN
- `help: requested` from a `--help` invocation → read `## Help` and run nothing
- fail (`sidecar exit` > 0) → a tier failed, or a WARN landed under `--strict`; quote the findings
  table verbatim inside a markdown code block, and fix nothing until the user has read it
- success (`sidecar exit` = 0) → report `errors` and `warnings`, then work the table top to bottom
- `--quick` reports inline and writes nothing, `--strict` promotes warnings to errors
- IF `--quick`, STOP after the inline report; `audit_file: none` confirms it, and nothing is appended

1. READ the table and group the rows by tier, since one broken shared file fails many skills at once
2. NAME the tier each failure landed in, since the tier says how far the sidecar got before it broke
3. TREAT a `t0` row as the most urgent, since a file that will not parse never ran at all
4. TREAT a `t3` row as a lie the exit code told, since the case returned 0 and proved nothing
5. QUOTE the `detail` column verbatim for every FAIL, since it carries the path or the repair
6. RUN the handover's per-skill line to read one failure in full, rather than re-running the tree
7. STOP after reporting; a repair is the user's to approve, and the tool mutates nothing itself

## the artifact
append one entry to `[audit_file]`, in the shape under `## the entry` below:

- the heading reads `## Smoke Audit #[next_audit]: [timestamp]`, both taken from the telemetry
- `state` is the scan counts and the probes directory, as hyphen bullets, one clause each
- `results` is the skill/tier/result/detail table the sidecar printed, as a markdown table
- `telemetry` is the sidecar's whole output, fenced and unedited, pasted last
- CREATE the file first if it does not exist, with `# <audit_file>` as its only line
- the sidecar names the path and the count and writes nothing, so a ci run leaves no entry
- the run writes nothing under that directory itself, so an absent file means nobody recorded a run

## the entry
> the artifact this skill appends to; `/gitgud:audit` grades the shape on its next run

# .construct/maintainer/test-skills/YYYY-MM-DD.md
one file per day, appended to by every run:

- an entry captures one run at a moment in time, so it is never edited after the fact
- lines are hyphen bullets holding a single clause, capped at 100 characters

## Smoke Audit #1: YYYY-MM-DD HH:MM

### state
the sidecars scanned, the two counts, the skills still without a case, and the probes directory

*example:*
> - scanned: 32 sidecar(s), 0 error(s), 0 warning(s)
> - probes: .construct/maintainer/test-skills/probes, kept: no

### results
the table the sidecar printed, one row per tier per skill

*example:*
> | gitgud:audit | t3-artifact | ok | 6 check(s), 0 note(s), 0s |

### telemetry
the sidecar's whole output, fenced and unedited

## the tiers
each tier runs only when the one before it passed, so one break reports once rather than four times:

- `t0` parses the file: `bash -n`, the shebang, shellcheck at error level, and the tracked exec bit
- `t1` asks it two questions: `--help` prints its marker, and an unknown flag is refused
- a refusal is any non-zero exit, since `fatal:` and `usage:` both refuse and the wording is nobody's
- a confirm gate refuses too, by pricing the run and stopping before it ever parses a flag
- the flag question is asked only of a skill whose `argument-hint` declares nothing past its flags
- a skill taking prose or a path reads a dash-leading word as its own argument, and is right to
- the hint is the declaration, so the doc decides which skills the question even applies to
- `t2` resolves what the sidecar declares about itself, reading its text and never running it
- `t3` runs `--test`, which is the only tier that executes the skill's file at all
- nothing here does the skill's work; a real run belongs to the trigger a user invokes on purpose
- a `t0-mode` row is the break that only ever lands on someone else's machine, so it is an error here

## what t2 resolves
every check reads the sidecar's own text, so a broken reference is named whether or not it runs:

- `source` stats every `# shellcheck source=` path, since a sourced file dying takes the plugin down
- ci runs `shellcheck --severity=warning`, where a missing source is SC1091 at info and passes
- so this tier is the only gate in the repo that fails a sourced file that moved or was deleted
- `see` stats every path on the `@see` line, which is how a rename that missed one gets caught
- a missing FILE on that line is a failure, and a missing DIRECTORY is a note, never a failure
- an artifact directory is written by a run nobody has made yet, so its absence proves nothing
- `tool` resolves every binary the file guards on with `command -v`, naming a machine gap as one

## the --test contract
every sidecar answers `--test` the same way, so the case is COPIED rather than written:

```text
case " $* " in *" --test "*) echo "test: ok"; exit 0;; esac
```

- it sits directly below the `--help` case, above every preflight and every confirm gate
- a test that has to pay for a confirm is a test nobody runs, which is why it sits that high
- the line is identical in all 32 sidecars: no path, no invocation name, nothing to paste wrong
- it proves the file parses and the guards above it returned, and deliberately nothing more
- the checks that need a sidecar's declarations live in `t2`, which reads them from outside
- one shared helper for this would be three byte-identical copies, one per plugin, to print a marker

## Verify
> not part of the trigger; these run after a doc or a sidecar changes

- RUN `.claude/skills/test-skills/test-skills.sh` after moving a shared file or renaming any path
- EXPECT zero warnings, since ci runs `--strict` and every sidecar already carries the case
- CONFIRM a new sidecar carries the `--test` case, since `validate-skills` warns and does not block
- CONFIRM this sidecar reads `100755` under `git ls-files -s`, since the disk bit lies
- FIX every `t0-mode` row, since that break reaches only the people who installed from a clone
- RERUN a disagreeing `t3` row scoped to that one path, since this sidecar writes no scratch to keep

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

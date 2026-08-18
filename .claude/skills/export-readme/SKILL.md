---
name: export-readme
model: opus
effort: high
license: MIT
compatibility: requires bash, jq, git
description: the readme is the source of truth for every skill's frontmatter (saves report to .construct/)
argument-hint: "[--help] [--check] [--quick] [--strict] <text> [--test]"
when_to_use: "Editing any skill's frontmatter or preamble, an output style copy, or wiring a new section into the export map. Also after ANY README.md edit, since each plugin root carries a byte-identical copy, or when a managed region and its readme section disagree."
disable-model-invocation: true
metadata:
  artifact: .construct/maintainer/export-readme/
---

# Instructions

## Telemetry
```!
.claude/skills/export-readme/export-readme.sh $ARGUMENTS
echo "sidecar exit: $?"
```
- it already ran, so there is no command to issue
- no argument EXPORTS: every unblocked drifted region is rewritten from its readme section
- `--check` reports and writes nothing, and skill names scope either mode
- `mapped: N target(s)` → what the map named, counting every copy a listed section fans out to
- `in_sync` / `drift` / `blocked` → the three states a target can be in, and they sum to `mapped`
- `listing: N/1536 chars at its widest` → the widest skill listing, which truncates silently at the cap
- `help: requested` from a `--help` invocation → read `## Help` and run nothing
- fail (`sidecar exit` > 0) → an ERROR blocked a section, or `--check` found drift; quote the
  drift table and the findings verbatim in a code block, and edit nothing until the user has read it
- a `--- refused:` diff is the one finding to raise first, since it names an edit about to be lost
- success (`sidecar exit` = 0) → report `drift` and `exported`, then re-run `--check` to confirm
  `drift: 0`, since the export is idempotent by contract
- a sandboxed run cannot write `.claude/skills/*/SKILL.md`; that is a partial export, not a pass

## the artifact
append one entry to `[audit_file]`, in the shape under `## the entry` below:

- the heading reads `## Export Audit #[next_audit]: [timestamp]`, both taken from the telemetry
- `state` is what the run measured, as hyphen bullets, one clause each
- `findings` is the ERROR and WARN table the sidecar printed, or one bullet saying none held
- `telemetry` is the sidecar's whole output, fenced and unedited, pasted last
- CREATE the file first if it does not exist, with `# <audit_file>` as its only line
- the sidecar names the path and the count and writes nothing, so a run nobody records leaves none

## the entry
> the artifact this skill appends to; `/gitgud:audit` grades the shape on its next run

# .construct/maintainer/export-readme/YYYY-MM-DD.md
one file per day, appended to by every run:

- an entry captures one run at a moment in time, so it is never edited after the fact
- lines are hyphen bullets holding a single clause, capped at 100 characters

## Export Audit #1: YYYY-MM-DD HH:MM

### state
the mode, the source and map, the four target counts, the widest listing, and what exported

*example:*
> - mode: export, source README.md mapped through map.json
> - targets: 52 mapped, 51 in sync, 1 drifted, 0 blocked
> - exported: 1 file(s)

### findings
the ERROR and WARN table the sidecar printed, or one bullet saying every rule held

*example:*
> | WARN | README.md:1204 | listing | 1489/1536 chars, close to the truncation cap |

### telemetry
the sidecar's whole output, fenced and unedited

## the shape
the readme's mapped sections are the source of truth for every managed region:

- a skill section is one bare invocation fence, one ```yaml fence, then the preamble markdown after it
- the yaml fence's inner `--- ... ---` becomes the skill's frontmatter, verbatim
- everything after the yaml fence, to the next heading, becomes the skill's preamble, verbatim
- the invocation fence is readme display sugar and never lands in a skill file
- `.claude/skills/export-readme/map.json` is one flat object: exact heading line -> target path
- a value may be a list, so one section lands in every copy that has to agree byte for byte
- a skill's managed region runs from line 1 to its first `# ` or `## ` body heading; the body
  below that heading belongs to the skill and is never touched

## the output style
`### Output Style` maps to one `output-styles/operator.md` per plugin and `### Subagent Style` to
one `subagent-styles/operator.md`; the copies exist so each plugin reaches its own `CLAUDE_PLUGIN_ROOT`:

- a style file carries no body heading, so its managed region is the whole file
- it earns `name` and `description` and nothing else; kind, license and the listing cap route an
  invocation a style never has
- `name:` must match the file, not a folder, since a style owns a file rather than a directory
- full runs sweep `plugins/*/output-styles/*.md` and its `subagent-styles/` sibling; an unmapped
  copy is an ERROR, since drifting unseen is the exact failure the fan-out exists to stop
- the subagent copy earns a 2500-byte cap, since every skill pastes it into every invocation
- over the cap is an ERROR that blocks its own section: cut a rule, never wrap one
- never edit a copy: fix the readme section, then re-export all three

## the scripts
a section may map to a shell script instead of a skill doc; NO section does today, since the
`shared/` libraries were unhooked once none of them fanned out to every plugin:

- a script section carries one ```bash fence; the fence's inner lines become the file, verbatim
- the prose around the fence is readme documentation and never lands in a copy
- a script has no frontmatter, so every yaml rule skips it; the fence must open `#!/bin/bash`
- the whole file is the managed region and a stale copy is replaced whole; there is no merge,
  since two edited copies is a mistake not a branch
- a data file cannot be a target at all, since the fence must open with a shebang
- `shared/secrets.sh` is duplicated in operator and retardify, and `/gitgud:audit` md5s the copies
- that audit is now the ONLY thing comparing them, so a red `Shared Drift` is the whole signal
- never edit a copy alone: change both, then re-run `/gitgud:audit` to prove they still match

## the readme copies
`README.md` maps to one copy per plugin root, and this entry names no section: the source file
itself is what lands, byte for byte, since an install takes one plugin's directory and no sibling:

- the whole file is the region and `cp` is the whole export; a render that shed one trailing blank
  would break the only contract this target has
- a copy carries no frontmatter, no heading and no fence, so `cmp` is every check it gets
- an absent copy is drift and not an ERROR: unlike a skill there is no body to invent, so a plugin
  added to the map earns its copy on the next apply
- a copy mapped into a directory that is not there is the one ERROR, since that is a typo
- full runs sweep `plugins/*/README.md` too, so a new plugin's copy cannot drift unmapped
- relative links resolve from the repo root, so `LICENSE` and every `plugins/...` link is dead in a
  copy one level down; byte-identical is the contract and those links are what it costs
- never edit a copy: fix the readme, then re-export all three

## the two modes
- a bare run exports: every unblocked drifted region is rewritten from its readme section
- `--check` writes nothing and exits 1 on any drift or ERROR; this is the one mode ci runs
- the drift table names each skill, which half moved (frontmatter, preamble, or both), the line
  delta, and which side moved last
- scope either mode with skill names (`credentials` or `operator:credentials`; `readme` scopes
  its own fan-out)
- the map and the source are fixed paths, edited by hand; no flag swaps either one

## the checks
this tool owns every frontmatter and preamble rule, judged at the readme source before anything
lands; validate-skills owns the body, the sidecar, the pairing, and the index, and nothing else:

- required fields: `name`, `license`, `compatibility`, `description` on every skill; a trigger
  adds `model` and `effort`, which route an invocation and are dead config on a spec
- `metadata.kind` is declared; `kind: trigger` sets `disable-model-invocation: true`, a spec must not
- `description` stays at or under 110 characters; over the cap is a WARN, since the fix is a
  rewrite, and a short description that already says the whole thing is not padded to a floor
- descriptions read in the default output style, lowercase with capitals held for proper nouns
  and ids; a reviewer's rule the script never grades
- `description` + `when_to_use` stays under the 1536 listing cap the harness truncates silently;
  past 1228 is a WARN, past the cap is an ERROR, since landing silent trigger loss is worse
- `name:` must match the skill's folder, so a mis-mapped heading cannot overwrite a sibling
- a script section earns none of the yaml rules; a missing ```bash fence, or one not opening
  `#!/bin/bash`, is its one ERROR
- a readme copy earns none of them either; its plugin directory missing is its one ERROR
- a heading the readme lacks, a duplicated heading, a section with no yaml fence, or a mapped
  file that does not exist are each an ERROR naming the exact readme or skill line
- full runs sweep coverage both ways: a SKILL.md, style or readme copy on disk with no map
  entry is an ERROR, and a catalog `####` heading the map never names is a WARN; scoped runs skip it
- an ERROR blocks only its own skill; every other drifted section still exports

## the refusal
drift can be legitimate in either direction, so the fresher copy is never written over:

- the NEWER column names which side moved last, read from file mtimes, since the edit that caused
  the drift is usually still uncommitted
- `copy` means the skill side is the fresher one, and exporting over it would discard that edit
- a `copy` row is an ERROR that blocks its own section, prints its diff inline, and lets every
  other section export
- the fix is always the same: move that edit INTO its readme section, then re-run
- the source mtime is file-level, so any readme edit marks every row `readme`; it bounds the
  question rather than answering it, and `copy` is the row that actually needs a human
- after an export, `--check` must report `drift: 0`; the export is idempotent by contract

## Verify
> not part of the tool; these run after the readme or a copy changes

- RUN `.claude/skills/export-readme/export-readme.sh` after ANY README.md edit, since the plugin copies track the whole file, not just the mapped sections
- RECONCILE every copy_newer refusal deliberately; source of truth means the readme wins by default, not always
- FIX every ERROR in the readme section the finding points at, then re-run
- RUN `.claude/skills/validate-skills/validate-skills.sh` after an export, since the skill docs just changed
- RE-RUN `/gitgud:audit` after editing either secrets.sh copy, since nothing else compares them now
- COMMIT the readme and every exported copy together; a partial commit reintroduces the drift

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

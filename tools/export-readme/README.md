---
name: export-readme
description: "The readme catalog is the source of truth: each skill section exports onto its SKILL.md top, drift reported first."
when_to_use: "Editing any skill's frontmatter or preamble, reviewing catalog drift after a README.md edit, or wiring a new skill section into the export map. Also when a skill top and its readme entry disagree."
metadata:
  kind: spec
---
# export-readme

## the shape
the readme's `#### <Skill>` catalog sections are the source of truth for every skill's top:

- a section is one bare invocation fence, one ```yaml fence, then the preamble markdown after it
- the yaml fence's inner `--- ... ---` becomes the skill's frontmatter, verbatim
- everything after the yaml fence, to the next heading, becomes the skill's preamble, verbatim
- the invocation fence is readme display sugar and never lands in a skill file
- `tools/export-readme/map.json` is one flat object: exact heading line -> SKILL.md path
- a skill's managed region runs from line 1 to its first `# ` or `## ` body heading; the body
  below that heading belongs to the skill and is never touched

## the two modes
- check is the default, mutates nothing, and exits 1 on any drift or ERROR; this is the ci mode
- the drift table names each skill, which half moved (frontmatter, preamble, or both), and the
  line delta; `--diff` appends the unified diff per skill for reconciliation
- `--apply` rewrites every unblocked drifted region; `--strict` promotes WARNs to the exit code
- scope either mode with skill names (`credentials` or `operator:credentials`)
- `--map` and `--source` swap the config and the readme, which is how the fixture tests run

## the checks
this tool owns every frontmatter and preamble rule, judged at the readme source before anything
lands; check-skills owns the body, the sidecar, the pairing, and the index, and nothing else:

- required fields: `name`, `license`, `compatibility`, `description` on every skill; a trigger
  adds `model` and `effort`, which route an invocation and are dead config on a spec
- `metadata.kind` is declared; `kind: trigger` sets `disable-model-invocation: true`, a spec must not
- `description` holds 100-110 characters; outside the band is a WARN, since the fix is a rewrite
- descriptions read in the default output style, lowercase with capitals held for proper nouns
  and ids; a reviewer's rule the script never grades
- `description` + `when_to_use` stays under the 1536 listing cap the harness truncates silently;
  past 1228 is a WARN, past the cap is an ERROR, since landing silent trigger loss is worse
- `name:` must match the skill's folder, so a mis-mapped heading cannot overwrite a sibling
- a heading the readme lacks, a duplicated heading, a section with no yaml fence, or a mapped
  file that does not exist are each an ERROR naming the exact readme or skill line
- full runs sweep coverage both ways: a SKILL.md on disk with no map entry is an ERROR, and a
  catalog `####` heading the map never names is a WARN; scoped runs skip the sweep
- an ERROR blocks only its own skill; every other drifted section still exports

## the confirm contract
drift can be legitimate in either direction, so nothing is written without a human decision:

- the agent runs the check, pastes the drift table in chat, and waits for the user to confirm
- a skill-side edit worth keeping is moved INTO its readme section first, then the export re-lands it
- on a tty, `--apply` prompts before writing; headless, `--apply` refuses without `--yes`
- after an apply, the same check must report `drift: 0`; the export is idempotent by contract

```text
VERIFY - not part of the tool
- RUN `tools/export-readme/export-readme.sh` after editing README.md catalog sections or any skill top
- RECONCILE every drift row deliberately; source of truth means the readme wins by default, not always
- FIX every ERROR in the readme section the finding points at, then re-run
- RUN `tools/check-skills/check-skills.sh` after an apply, since the skill docs just changed
```

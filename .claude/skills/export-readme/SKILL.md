---
name: export-readme
description: "The readme is the source of truth: each mapped section exports onto its skill top, style, or script copy."
when_to_use: "Editing any skill's frontmatter or preamble, a style or secrets.sh copy, or wiring a new section into the export map. Also after a README.md catalog edit, or when a managed region and its readme section disagree."
metadata:
  kind: spec
---
# export-readme

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
`## Output Style` maps to one `output-styles/operator.md` per plugin, and the three copies exist
only because a plugin has to reach its own file through `CLAUDE_PLUGIN_ROOT`:

- a style file carries no body heading, so its managed region is the whole file
- it earns `name` and `description` and nothing else; kind, license and the listing cap route an
  invocation a style never has
- `name:` must match the file, not a folder, since a style owns a file rather than a directory
- full runs sweep `plugins/*/output-styles/*.md` too; an unmapped copy is an ERROR, since drifting
  unseen is the exact failure the fan-out exists to stop
- never edit a copy: fix the readme section, then re-export all three

## the scripts
`## Secrets` maps to one `shared/secrets.sh` per plugin, the same fan-out for the same reason: an
install copies one plugin's directory and never a sibling, so the file cannot be shared:

- a script section carries one ```bash fence; the fence's inner lines become the file, verbatim
- the prose around the fence is readme documentation and never lands in a copy
- a script has no frontmatter, so every yaml rule skips it; the fence must open `#!/bin/bash`
- the whole file is the managed region and a stale copy is replaced whole; there is no merge,
  since two edited copies is a mistake not a branch
- full runs sweep `plugins/*/shared/secrets.sh` too, so a new plugin's copy cannot drift unmapped
- `/gitgud:audit` reports copy drift and stays read-only; `--apply secrets` is the repair
- never edit a copy: fix the readme fence, then re-export all three

## the two modes
- check is the default, mutates nothing, and exits 1 on any drift or ERROR; this is the ci mode
- the drift table names each skill, which half moved (frontmatter, preamble, or both), and the
  line delta; `--diff` appends the unified diff per skill for reconciliation
- `--apply` rewrites every unblocked drifted region; `--strict` promotes WARNs to the exit code
- scope either mode with skill names (`credentials` or `operator:credentials`, `secrets` for the copies)
- `--map` and `--source` swap the config and the readme, which is how the fixture tests run

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
- a heading the readme lacks, a duplicated heading, a section with no yaml fence, or a mapped
  file that does not exist are each an ERROR naming the exact readme or skill line
- full runs sweep coverage both ways: a SKILL.md, style or secrets copy on disk with no map entry
  is an ERROR, and a catalog `####` heading the map never names is a WARN; scoped runs skip the sweep
- an ERROR blocks only its own skill; every other drifted section still exports

## the confirm contract
drift can be legitimate in either direction, so nothing is written without a human decision:

- the agent runs the check, pastes the drift table in chat, and waits for the user to confirm
- a skill-side edit worth keeping is moved INTO its readme section first, then the export re-lands it
- on a tty, `--apply` prompts before writing; headless, `--apply` refuses without `--yes`
- after an apply, the same check must report `drift: 0`; the export is idempotent by contract

```text
VERIFY - not part of the tool
- RUN `.claude/skills/export-readme/export-readme.sh` after editing README.md mapped sections or any exported copy
- RECONCILE every drift row deliberately; source of truth means the readme wins by default, not always
- FIX every ERROR in the readme section the finding points at, then re-run
- RUN `.claude/skills/validate-skills/validate-skills.sh` after an apply, since the skill docs just changed
- RE-RUN every sidecar sourcing secrets.sh after its fence changes, since a pattern change moves their findings
- COMMIT the readme and every exported copy together; a partial commit reintroduces the drift
```

---
name: validate-skills
description: "Shape every skill pair must hold: the SKILL.md, its sidecar, and the frontmatter that gates it. Validates them."
argument-hint: "[--help] [--strict] [--keep] [<path>]"
when_to_use: "Authoring or editing any SKILL.md or its sidecar, adding a skill to a plugin, or deciding whether a skill is a trigger or a spec. Also when a listing looks truncated or a skill fails to load."
metadata:
  kind: spec
---
# Instructions

## the pair
a skill is one folder, named for its trigger, holding exactly two files:

- `SKILL.md` carries the frontmatter and the numbered steps, and nothing above them
- `<name>.sh` carries the sidecar, and the wayfinding header for the whole pair
- the doc has no wayfinder of its own, since two headers that can disagree is worse than one
- frontmatter opens line 1 with `name` matching the folder, and a `description` a reader sees
- `metadata.kind` is declared rather than guessed, and decides the rest of the frontmatter
- `kind: trigger` acts on the repo, so it sets `disable-model-invocation: true`; prose is not a gate
- `kind: spec` describes a shape, so it stays auto-loading and never sets that flag
- every frontmatter rule above is judged by `.claude/skills/export-readme/export-readme.sh` at
  the readme source; this pair's own checks stop at the body, the sidecar, the pairing, and the index

## the listing budget
`description` and `when_to_use` are the whole listing; everything else loads only once a skill does:

- the harness truncates the two of them, combined, at 1536 characters, and says nothing when it does
- past the cap the tail is dropped, so a skill can lose the clause naming when it fires and still list
- put the use case first, since a truncated listing keeps its opening and loses its end
- `description` says what the skill does; `when_to_use` carries trigger phrases and example requests
- the body is charged only when the skill loads, so long reference prose belongs under the frontmatter
- longer still belongs in a sibling file the body names, which costs nothing until it is read
- `metadata` is free-form and the harness ignores it, so it never counts against the cap
- export-readme measures the cap at the readme source, where the text is edited, not here

## the telemetry block
a doc that runs a sidecar opens its body with one, in this shape and no other:

```text
## Telemetry
```!
<the sidecar call, and `echo "sidecar exit: $?"`>
```
- it already ran, so there is no command to issue
- fail (`sidecar exit` > 0) → what to report
- success (`sidecar exit` = 0) → what to read, and where to continue
```

- the heading opens straight onto the ```! block, since a blank line there reads as a gap
- the bullets close it flush, and each names one branch the sidecar can actually report
- a sidecar call under any other heading is an ERROR; unlabelled telemetry is telemetry nobody reads
- numbered steps start AFTER the block, at 1, since reading the output is not a step
- a spec that runs nothing carries no telemetry section at all, and `log` is the one example
- an auto-loading spec guards the call on `$ARGUMENTS`, since a bare load must run nothing

## the help section
every skill answers `--help` the same way, so the section is COPIED rather than written. it sits
directly above `## Output Style`, and this doc's own `## Help` below is the canonical text:

- the fence holds placeholders, never one skill's filled values, so all of them stay identical
- that is what makes this one comparison instead of a shape per skill; a drift is a bad paste
- `HELP_BLOCK` in the sidecar is the source, and the doc is compared to it whole
- every field prints on every run, and one with nothing to say prints `none`
- each value is copied from the source named beside it, so two runs of one skill agree
- the sidecar carries the matching guard, since the ```! block runs before the doc is read
- a help invocation refused only in prose has already paid for the run it was refusing
- the guard prints `help: requested` and exits 0, so the doc branches on a line rather than silence
- that marker earns a telemetry bullet, since a bare exit 0 otherwise reads as a clean run
- a doc that runs no sidecar carries the section anyway, and `log` is the one example

## the subagent style
the output style is opt-in and a subagent never inherits one, so the LAST body heading of every
doc is `## Subagent Style`, and it cats that plugin's compressed brief into the turn:

```text
awk 'NR>1 && /^---$/ {p=1; next} p' "${CLAUDE_PLUGIN_ROOT}/subagent-styles/operator.md"
```

- it closes the doc, so the task instructions lead and the format rule lands last
- a `## ` section after it is an ERROR, since that section would read as the conclusion instead
- the command is compared byte for byte; a paraphrase cats nothing and reports the same clean run
- `CLAUDE_PLUGIN_ROOT` resolves per plugin, so one identical line serves every skill in the tree
- the awk sheds frontmatter, which is config for the picker and instruction to nobody
- the block carries no numbered step, since step numbers climb once across a whole doc
- it carries no bullet either; the missing-file case is already an ERROR two layers up
- a plugin that ships skills ships `subagent-styles/operator.md`, or the block cats an empty file
- the copies are one readme section exported three ways, never three files edited three times

## the body
frontmatter and pairing can both be correct while the body is structurally broken, which is how a
pasted archive shape corrupted two docs and every gate still reported clean:

- the body opens on `# Instructions`, the one h1 above every `## ` section, so the doc has a seam
- that h1 is never the template boundary; counting it as one switches the step check off silently
- the first `# ` heading after it is the boundary: above it the doc instructs, below it templates
- step numbers above that boundary climb, each appearing once; a repeat is two blocks fighting
- a heading closing no backtick it opened ate the line it was meant to reference
- an archive shape names the kind its own template h1 declares, never a sibling's
- a `<kind>` or `<Kind>` placeholder means the generic shape was pasted and never written
- the kind is read from that h1 and never from a mention, since a findings example may name a sibling
- an audit directory is named for the SUBJECT audited, so `git` is owned by `/gitgud:audit`
- a verify list reads under `## Verify`; fenced, it renders as sample output a reader skips
- no doc is required to carry one, since most fold the same steps into their numbered procedure

## the two blocks
every sidecar prints the same pair, in the same order, so each trigger doc reads one contract.
the name in a block header is the INVOCATION, so the header and the `/` menu can never disagree:

```text
=== /plugin:skill telemetry ===
key: value

=== /plugin:skill handover ===
# a note explaining the block, or why it is empty
git command one
git command two
=====================
```

- `telemetry` is what was measured; the trigger doc branches on it
- `handover` is what the user runs; every line is runnable as written, notes stay commented
- `trigger` is the optional third block: what the trigger runs as a tool call, never a paste
- a sidecar that needs to mutate emits the command instead of running it, into either block
- close every trigger with ONE copy-paste bash block holding the handover, in that same order

## the exec bit
every sidecar and every hook is tracked `100755`, since git records the mode an install copies:

- a `chmod` that never reached the index fixes the authoring machine and nobody else's
- the failure lands on the user as `permission denied` from a path they did not write
- `inject-support.sh` shipped `100644` and died on the first outside install, which is why this is a gate
- the check reads `git ls-files -s`, never the disk, so a local bit nobody committed still fails
- an untracked file has no recorded mode yet, so it is skipped rather than guessed at
- hooks pair with no doc, so they are walked repo-wide once instead of per skill
- the repair is `git update-index --chmod=+x <path>`, which the finding prints in full
- `shared/*.sh` stays `100644` on purpose, since those are sourced and never exec'd

## the read-only contract
- a sidecar may fetch, since that moves only remote-tracking refs, and may call the github api
- a sidecar may NOT stash, switch, merge, push, reset, restore, clean, or delete a branch
- a sidecar's commands are not tool calls, so neither the deny floor nor the hook ever sees them
- that is the whole reason for the rule: a sidecar running them was a silent bypass of both gates
- where a trigger genuinely needs to mutate, the floor opens a narrow allow and the TRIGGER runs it,
  which keeps the command in front of the gate; the sidecar emits it into a `trigger` block instead
- a step earns that block only by ADDING safety: `@git-continue`'s sync is recoverable at every
  step, and `@git-fresh`'s backup is the one line that makes the rest of its handover survivable
- a step that SPENDS safety never earns it, however convenient — clean, reset and force-switch
  stay in the handover no matter how many times the same paste gets asked for
- `plugins/gitgud/shared/handover.sh` carries the shared preflights, queries, and block emitters
- default branch resolution goes through `git_default_branch`, since `symbolic-ref` is denied

## Verify
> not part of the trigger; these run after a doc or a sidecar changes

- RUN `.claude/skills/validate-skills/validate-skills.sh` after touching a trigger doc or its sidecar; pass a path to scope it
- RUN `.claude/skills/export-readme/export-readme.sh` after touching frontmatter or a preamble; the readme is their source
- CONFIRM a new sidecar or hook reads `100755` under `git ls-files -s <path>`, since the disk bit lies
- FIX every ERROR, since each one breaks a rule this spec states outright
- STOP on a `secret` finding and ask the user before truncating it; the key needs rotating first
- JUSTIFY or fix every WARN; the sidecar tolerates them, the next reader may not
- ANSWER the checklist it prints, since those rules are the ones no script can judge

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

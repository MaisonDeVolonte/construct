---
name: nuke
model: opus
effort: max
license: MIT
compatibility: requires bash, git
description: price what a hard reset would take, take the backup that makes it survivable, then hand back the rest
argument-hint: "[--help]"
disable-model-invocation: true
metadata:
  kind: trigger
---
**start over, knowingly:** the cost is counted and backed up before the reset
- reports every commit, file and branch the reset would take
- takes the backup itself, which is what makes the reset survivable
- never resets, cleans or deletes; each of those is yours to run

# Instructions

## Telemetry
```!
"${CLAUDE_PLUGIN_ROOT}"/skills/nuke/nuke.sh $ARGUMENTS
echo "sidecar exit: $?"
```
- `help: requested` → the run was refused before it started; `## Help` below is the whole turn
- it already ran, so there is no command to issue
- fail (`sidecar exit` > 0) → abort and report: "<raw terminal error>"
- success (`sidecar exit` = 0) → continue to step 1

1. run the native shell command exactly as specified
  ```bash
  plugins/gitgud/skills/nuke/nuke.sh
  ```
  - fail (`sidecar exit` > 0) → abort and report: "<raw terminal error>"
  - success (`sidecar exit` = 0) → continue to step 2

2. run the `=== /gitgud:nuke trigger ===` block, if the sidecar emitted one
    - it appears only on a dirty tree; a clean tree has nothing to back up, so skip to step 3
    - run its single `git stash push` line as its own tool call, exactly as printed
    - the floor allows only `git stash push -u -m 'git-fresh-*'`; anything else is handed over
    - `-u` and not `-a` on purpose: `git clean -fd` never touches ignored files, so stashing them
      would collect what the reset was never going to destroy, `.env` included
    - non-zero exit → STOP, report the raw error, and hand over NOTHING
      - the destructive block is safe to paste only once the backup exists
      - a reset offered after a failed backup is the one outcome this trigger must never produce

3. prove the stash landed before naming a single destructive command
    ```bash
    git stash list
    ```
    - the entry named in the trigger block MUST appear; if it does not, STOP and report that
    - never infer the stash from a zero exit code alone, since the proof is what step 5 rests on
    - name the entry in the report, so the user can find it without trusting this step

4. report the cost, then the handover, then STOP
    ```text
    - /gitgud:nuke telemetry data

    - the backup is already taken: [stash entry name]

    - pasting the block below will:
      - DISCARD [commits the reset discards] local commit(s) on [default branch]
      - DELETE [branches pending deletion] local branch(es): [pending branch names]
      - THROW AWAY [untracked files at risk + modifications at risk] working file(s), now stashed
    ```
    - close with one copy-paste bash block holding every handover command, in that same order

    NEVER run a clean, reset, switch or branch delete, and never offer to; handing those
    commands over IS the deliverable

    - the paste is the confirmation, so no typed phrase gates a step the user runs themselves
    - `git stash pop` restores the backup, and the floor allows it, but only on request
    - the deny list and `block-destructive-git.sh` both refuse the destructive commands, which is the design
      rather than an obstacle to work around: they are the user's to run, never the agent's

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

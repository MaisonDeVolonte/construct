---
name: backup
model: opus
effort: high
license: MIT
compatibility: requires bash, git
description: snapshot the history and the working tree, verify that snapshot, then hand back every restore command
argument-hint: "[--help] [--test]"
disable-model-invocation: true
---
**a snapshot verified, not assumed:** worth typing before anything destructive
- worth typing before any reset, rebase, history rewrite or bulk delete
- nothing to configure; the destination is fixed and it overwrites nothing
- never restores anything; the restore commands are handed back to you

# Instructions

## Telemetry
```!
"${CLAUDE_PLUGIN_ROOT}"/skills/backup/backup.sh $ARGUMENTS
echo "sidecar exit: $?"
```
- `help: requested` → the run was refused before it started; `## Help` below is the whole turn
- it already ran, so there is no command to issue
- fail (`sidecar exit` > 0) → abort and report: "<raw terminal error>"
- a failed snapshot means STOP, never continue into the destructive work it was taken for
- success (`sidecar exit` = 0) → continue to step 1

1. report the snapshot, then the restore block, then STOP
    ```text
    - /gitgud:backup telemetry data

    - the snapshot is taken and verified: [backup location]
      - [git objects copied] objects, [working files copied] working file(s)
      - [modifications captured] modification(s) and [untracked captured] untracked file(s)
    ```
    - name the location in full, so the user can find it without re-running this trigger
    - close with the `=== /gitgud:backup handover ===` block as one copy-paste bash block

    - ignored files are deliberately absent, since `clean -fd` and `reset --hard` never touch them
    - the snapshot lives inside the repo, so `git clean -fdx` is the one command that eats it
    - `clean` is denied to the agent in every scope, so only the user can destroy a backup

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

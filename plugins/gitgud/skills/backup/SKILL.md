---
name: backup
model: opus
effort: high
license: MIT
compatibility: requires bash, git
description: snapshot the history and the working tree, verify that snapshot, then hand back every restore command
disable-model-invocation: true
metadata:
  kind: trigger
---
**a snapshot verified, not assumed:** worth typing before anything destructive
- worth typing before any reset, rebase, history rewrite or bulk delete
- takes no arguments; the destination is fixed and it overwrites nothing
- never restores anything; the restore commands are handed back to you

# Instructions

## Telemetry
```!
"${CLAUDE_PLUGIN_ROOT}"/skills/backup/backup.sh
echo "sidecar exit: $?"
```
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

## Output Style
```!
awk 'NR>1 && /^---$/ {p=1; next} p' "${CLAUDE_PLUGIN_ROOT}/output-styles/operator.md"
```

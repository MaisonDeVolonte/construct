---
name: backup
description: Snapshot history and working tree, verify the snapshot, then hand over the restore.
disable-model-invocation: true
metadata:
  kind: trigger
---
**/gitgud:backup:** Run ONLY on explicit `/gitgud:backup` command
- takes a full, verified snapshot of history and working tree into gitignored `tmp/backups/`
- takes no arguments and asks nothing; the destination is fixed and it overwrites nothing
- worth typing before any reset, rebase, history rewrite or bulk delete is in play
- never restores anything; the restore commands are handed over for the user to run

## voice

```!
awk 'NR>1 && /^---$/ {p=1; next} p' "${CLAUDE_PLUGIN_ROOT}/output-styles/operator.md"
```

- the block above already ran, and it is the output contract for this response
- it holds for this turn even when the user's active output style is something else
- an empty block means the plugin has no style file; continue, since voice never gates the work

## telemetry

```!
"${CLAUDE_PLUGIN_ROOT}"/skills/backup/backup.sh
echo "sidecar exit: $?"
```

1. read the block above; it already ran, so there is no command to issue
  - fail (`sidecar exit` > 0) → abort and report: "<raw terminal error>"
    - a failed snapshot means STOP, never continue into the destructive work it was taken for
  - success (`sidecar exit` = 0) → continue to step 2

2. report the snapshot, then the restore block, then STOP
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

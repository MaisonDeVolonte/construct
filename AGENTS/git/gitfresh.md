```javascript
/**
 * ==================================================
 * @file gitfresh.md - destructive hard-reset trigger
 * ==================================================
 * @description
 * - ran only on explicit `@gitfresh` command; for a broken, conflicted, or desynced workspace
 * - READ-ONLY: runs `AGENTS/git/gitaudit.sh` for context, then `AGENTS/git/gitfresh.sh` to measure
 * - the sidecar destroys nothing and backs nothing up; it prints what a reset would cost
 * - stash, clean, reset, switch and branch deletes are all denied, so the user runs every one
 * - the handover leads with the backup stash, so the first pasted line is the recoverable one
 * @see AGENTS.md, AGENTS/templates/git.md, AGENTS/git/gitfresh.sh, AGENTS/git/gitaudit.sh
 */
```

**@gitfresh:** Run ONLY on explicit `@gitfresh` command
- typically ran when the local workspace is broken, conflicted, or severely desynced
- reports every commit, file and branch a reset would destroy, before the user runs anything
- backs nothing up itself: the backup stash is the first line of the handover, not a side effect
- never cleans, resets, or deletes; each command is handed over for the user to run

1. run the native shell command exactly as specified
  ```bash
  AGENTS/git/gitaudit.sh
  ```
  - fail (exit code > 0) → abort and report: "<raw terminal error>"
  - success (exit code = 0) → continue to step 2

2. run the native shell command exactly as specified
  ```bash
  AGENTS/git/gitfresh.sh
  ```
  - fail (exit code > 0) → abort and report: "<raw terminal error>"
  - success (exit code = 0) → continue to step 3

3. report the cost, then the handover, then STOP
    ```text
    - @gitfresh telemetry data

    - pasting the block below will:
      - BACKUP [untracked files at risk + modifications at risk] into a named stash
      - DISCARD [commits the reset discards] local commit(s) on [default branch]
      - DELETE [branches pending deletion] local branch(es): [pending branch names]
    ```
    - close with one copy-paste bash block holding every handover command, in that same order

    NEVER run a clean, reset, stash or branch delete, and never offer to; handing the commands
    over IS the deliverable

    - the paste is the confirmation, so no typed phrase gates a sidecar that changes nothing
    - the deny list and `pretooluse.sh` both refuse these commands, which is the design rather
      than an obstacle to work around: they are the user's to run, never the agent's

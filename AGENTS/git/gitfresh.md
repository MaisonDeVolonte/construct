```javascript
/**
 * ==================================================
 * @file gitfresh.md - destructive hard-reset trigger
 * ==================================================
 * @description
 * - ran only on explicit `@gitfresh` command; for a broken, conflicted, or desynced workspace
 * - runs `AGENTS/git/gitaudit.sh` telemetry first, then requires an exact confirmation
 *   phrase before touching anything
 * - backs up all changes to an emergency stash, switches to trunk, and fetches from origin
 * - runs `AGENTS/git/gitfresh.sh --confirmed` only after explicit user confirmation
 * - gated: never cleans, resets, or deletes; it prints every command for the user to run by hand
 * @see AGENTS.md, AGENTS/templates/git.md, AGENTS/git/gitfresh.sh, AGENTS/git/gitaudit.sh
 */
```

**@gitfresh:** Run ONLY on explicit `@gitfresh` command
- typically ran when local workspace is broken, conflicted, or severely desynced
- backs up all tracked modifications (staged/unstaged) and untracked files into an emergency stash
- aborts active operations, switches to trunk, and fetches pristine state from origin
- never cleans, resets, or deletes a branch; each one is handed over for you to run yourself

1. run the native shell command exactly as specified
  ```bash
  AGENTS/git/gitaudit.sh
  ```
  - fail (exit code > 0) → abort and report: "<raw terminal error>"
  - success (exit code = 0):
    ```text
    - @gitaudit telemetry data
    
    - @gitfresh will:
      - BACKUP [SUM staged_files + unstaged_files + untracked_files] uncommitted/untracked changes
      - HAND OVER the commands that RESET [default_branch] to exactly match origin
      - HAND OVER the commands that DELETE the following local branches:
          - [local_branches]

    - to continue, type exactly: `Yes, nuke everything and start fresh!`
    ```
    - fail → "not exact match – @gitfresh aborted — nothing changed"
    - success → continue to next step

2. run the native shell command exactly as specified
  ```bash
  AGENTS/git/gitfresh.sh --confirmed
  ```
  - fail (exit code > 0) → abort and report: "<raw terminal error>"
  - success (exit code = 0) → report "@gitfresh telemetry", print the handover, then STOP

    NEVER run a clean, reset, or branch delete, and never offer to; handing the commands
    over IS the deliverable

    - close with one copy-paste bash block holding every handover command, in that same order
    - the deny list and `pretooluse.sh` both block these commands, which is the design, not
      an obstacle to work around: they are the user's to run, never the agent's

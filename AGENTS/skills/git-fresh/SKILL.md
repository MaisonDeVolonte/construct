---
name: git-fresh
description: Price a hard reset, take the backup itself, then hand over the destructive rest.
disable-model-invocation: true
metadata:
  kind: trigger
---
**@git-fresh:** Run ONLY on explicit `@git-fresh` command
- typically ran when the local workspace is broken, conflicted, or severely desynced
- reports every commit, file and branch a reset would destroy, before the user runs anything
- takes the backup itself, then hands over every command that cannot be undone
- never cleans, resets, switches or deletes a branch; each of those is the user's to run

## telemetry

```!
"${CLAUDE_PLUGIN_ROOT}"/skills/git-audit/git-audit.sh
echo "sidecar exit: $?"
```

1. read the block above; it already ran, so there is no command to issue
  - fail (`sidecar exit` > 0) → abort and report: "<raw terminal error>"
  - success (`sidecar exit` = 0) → continue to step 2

2. run the native shell command exactly as specified
  ```bash
  AGENTS/skills/git-fresh/git-fresh.sh
  ```
  - fail (`sidecar exit` > 0) → abort and report: "<raw terminal error>"
  - success (`sidecar exit` = 0) → continue to step 3

3. run the `=== @git-fresh trigger ===` block, if the sidecar emitted one
    - it appears only on a dirty tree; a clean tree has nothing to back up, so skip to step 4
    - run its single `git stash push` line as its own tool call, exactly as printed
    - the floor allows only `git stash push -u -m 'git-fresh-*'`; anything else is handed over
    - `-u` and not `-a` on purpose: `git clean -fd` never touches ignored files, so stashing them
      would collect what the reset was never going to destroy, `.env` included
    - non-zero exit → STOP, report the raw error, and hand over NOTHING
      - the destructive block is safe to paste only once the backup exists
      - a reset offered after a failed backup is the one outcome this trigger must never produce

4. prove the stash landed before naming a single destructive command
    ```bash
    git stash list
    ```
    - the entry named in the trigger block MUST appear; if it does not, STOP and report that
    - never infer the stash from a zero exit code alone, since the proof is what step 5 rests on
    - name the entry in the report, so the user can find it without trusting this step

5. report the cost, then the handover, then STOP
    ```text
    - @git-fresh telemetry data

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
    - the deny list and `pretooluse.sh` both refuse the destructive commands, which is the design
      rather than an obstacle to work around: they are the user's to run, never the agent's

---
name: git-backup
description: Snapshot history and working tree, verify the snapshot, then hand over the restore.
disallowed-tools: Write Edit
disable-model-invocation: true
---
```javascript
/**
 * ==============================================
 * @file SKILL.md - safe repo snapshot trigger
 * ==============================================
 * @description
 * - ran only on explicit `@git-backup` command; reach for it before anything destructive
 * - runs `AGENTS/skills/git-backup/git-backup.sh`, which takes the snapshot itself and verifies it
 * - the one trigger that needs no confirmation, since a copy destroys nothing it finds
 * - captures history and working tree separately, because a `.git` copy loses uncommitted work
 * - the restore is handed over, never run: putting files back overwrites what sits there now
 * @see AGENTS.md, AGENTS/templates/git.md, AGENTS/skills/git-backup/git-backup.sh, AGENTS/skills/git-fresh/SKILL.md
 */
```

**@git-backup:** Run ONLY on explicit `@git-backup` command
- takes a full, verified snapshot of history and working tree into gitignored `tmp/backups/`
- takes no arguments and asks nothing; the destination is fixed and it overwrites nothing
- worth typing before any reset, rebase, history rewrite or bulk delete is in play
- never restores anything; the restore commands are handed over for the user to run

## telemetry

```!
"${CLAUDE_PLUGIN_ROOT}"/skills/git-backup/git-backup.sh
echo "sidecar exit: $?"
```

1. read the block above; it already ran, so there is no command to issue
  - fail (`sidecar exit` > 0) → abort and report: "<raw terminal error>"
    - a failed snapshot means STOP, never continue into the destructive work it was taken for
  - success (`sidecar exit` = 0) → continue to step 2

2. report the snapshot, then the restore block, then STOP
    ```text
    - @git-backup telemetry data

    - the snapshot is taken and verified: [backup location]
      - [git objects copied] objects, [working files copied] working file(s)
      - [modifications captured] modification(s) and [untracked captured] untracked file(s)
    ```
    - name the location in full, so the user can find it without re-running this trigger
    - close with the `=== @git-backup handover ===` block as one copy-paste bash block

    - ignored files are deliberately absent, since `clean -fd` and `reset --hard` never touch them
    - the snapshot lives inside the repo, so `git clean -fdx` is the one command that eats it
    - `clean` is denied to the agent in every scope, so only the user can destroy a backup

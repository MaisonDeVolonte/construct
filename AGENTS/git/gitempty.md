```javascript
/**
 * ====================================================
 * @file gitempty.md - gated post-merge cleanup trigger
 * ====================================================
 * @description
 * - ran only on explicit `@gitempty` command; typically post-merge, but safe anytime
 * - runs `AGENTS/git/gitempty.sh` to stash work, prune dead remotes, and fast-forward trunk
 * - runs `AGENTS/git/gitaudit.sh` to classify branches (local/remote/ghost/zombie) for deletion
 * - gated: never deletes, and prints every deletion command for the user to run by hand
 * @see AGENTS.md, AGENTS/templates/git.md, AGENTS/git/gitempty.sh, AGENTS/git/gitaudit.sh
 */
```

**@gitempty:** Run ONLY on explicit `@gitempty` command
- typically ran post-merge but safe to run anytime
- stashes work, prunes dead remotes, fast-forwards trunk, and returns you to starting branch
- preserves unmerged branches and identifies merged branches eligible for deletion (local, remote, ghost, and zombie)
- never deletes anything; every deletion is handed over as a command for you to run yourself

1. run the native shell command exactly as specified
  ```bash
  AGENTS/git/gitempty.sh
  ```
  - fail (exit code > 0) → abort and report: "<raw terminal error>"
  - success (exit code = 0) → continue and report: "@gitempty telemetry"

2. run the native shell command exactly as specified
  ```bash
  AGENTS/git/gitaudit.sh
  ```
  - fail (exit code > 0) → abort and report: "<raw terminal error>"
  - success (exit code = 0): print the deletion commands for the user to run, then STOP

    NEVER run a deletion, and never offer to; handing the commands over IS the deliverable

    read `merged = yes OR absorbed = yes` as "safe", since a rebased branch reads merged = no
    forever; only `merged = no AND absorbed = no` is real unmerged work

    ```text
    - ignored: `main` and `production` are never deleted
  
    - skipped: merged = no AND absorbed = no, the only branches holding unshipped work
      - `branch_name`
  
    - local only deletions: safe, reachable = yes, and remote = no
      - `branch_name` → `git branch -d branch_name`

    - local & remote deletions: safe, reachable = yes, and remote = yes
      - `branch_name` → `git push origin --delete branch_name && git branch -d branch_name`
  
    - ghost deletions: safe (squash/rebase), reachable = no, and remote = no
      - `branch_name` → `git branch -D branch_name`

    - zombie deletions: safe (squash/rebase), reachable = no, and remote = yes (still on GitHub)
      - `branch_name` → `git push origin --delete branch_name && git branch -D branch_name`

    - remote only deletions: listed under `--- remote-only ---` with safe, no local branch
      - `branch_name` → `git push origin --delete branch_name`
    ```

    - state `absorbed: yes / merged: no` explicitly when it applies, so the user can see the
      branch is rebase-absorbed rather than take a deletion on trust
    - `-D` is required for any absorbed branch, since `-d` consults the same patch-id check
      that got it wrong
    - close with one copy-paste bash block holding every command above, in that same order
    - the deny list and `pretooluse.sh` both block these commands, which is the design, not
      an obstacle to work around: they are the user's to run, never the agent's

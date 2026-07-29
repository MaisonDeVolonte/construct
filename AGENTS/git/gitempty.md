```javascript
/**
 * ==========================================================
 * @file gitempty.md - destructive post-merge cleanup trigger
 * ==========================================================
 * @description
 * - ran only on explicit `@gitempty` command; typically post-merge, but safe anytime
 * - runs `AGENTS/git/gitempty.sh` to stash work, prune dead remotes, and fast-forward trunk
 * - runs `AGENTS/git/gitaudit.sh` to classify branches (local/remote/ghost/zombie) for deletion
 * - destructive: asks the user to confirm every branch-cleanup action before deleting
 * @see AGENTS.md, AGENTS/templates/git.md, AGENTS/git/gitempty.sh, AGENTS/git/gitaudit.sh
 */
```

**@gitempty:** Run ONLY on explicit `@gitempty` command
- typically ran post-merge but safe to run anytime
- stashes work, prunes dead remotes, fast-forwards trunk, and returns you to starting branch
- preserves unmerged branches and identifies merged branches eligible for deletion (local, remote, ghost, and zombie)

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
  - success (exit code = 0): ask the user to confirm any branch cleanup actions:

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
      that got it wrong; note that `pretooluse.sh` blocks `-D`, so hand those commands over

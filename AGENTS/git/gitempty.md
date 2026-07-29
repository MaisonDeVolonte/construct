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

    ```text
    - ignored: `main` and `production` are never deleted
  
    - skipped: unmerged branches that are not eligible for deletion
      - `branch_name`
  
    - local only deletions: merged = yes, reachable = yes, and remote = no
      - `branch_name` → `git branch -d branch_name`

    - local & remote deletions: merged = yes, reachable = yes, and remote = yes
      - `branch_name` → `git push origin --delete branch_name && git branch -d branch_name`
  
    - ghost deletions: merged = yes (squash/rebase), reachable = no, and remote = no
      - `branch_name` → `git branch -D branch_name`

    - zombie deletions: merged = yes (squash/rebase), reachable = no, and remote = yes (still on GitHub)
      - `branch_name` → `git push origin --delete branch_name && git branch -D branch_name`

    - remote only deletions: listed under `--- remote-only ---` with merged = yes, no local branch
      - `branch_name` → `git push origin --delete branch_name`
    ```

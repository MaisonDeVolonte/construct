---
name: git-empty
description: Prune dead tracking refs and hand over the trunk sync and every branch delete.
disable-model-invocation: true
metadata:
  kind: trigger
---
**@git-empty:** Run ONLY on explicit `@git-empty` command
- typically ran post-merge but safe to run anytime
- prunes dead tracking refs, then reports the trunk delta and every branch that is spent
- preserves unmerged branches and identifies the merged ones eligible for deletion
- never deletes anything; every deletion is handed over as a command for you to run yourself

## telemetry

```!
"${CLAUDE_PLUGIN_ROOT}"/skills/git-empty/git-empty.sh
echo "sidecar exit: $?"
```

1. read the block above; it already ran, so there is no command to issue
  - fail (`sidecar exit` > 0) → abort and report: "<raw terminal error>"
  - success (`sidecar exit` = 0) → report "@git-empty telemetry" and continue to step 2

2. run the native shell command exactly as specified
  ```bash
  AGENTS/skills/git-audit/git-audit.sh
  ```
  - fail (`sidecar exit` > 0) → abort and report: "<raw terminal error>"
  - success (`sidecar exit` = 0): merge its classification into the handover, then STOP

    NEVER run a deletion, and never offer to; handing the commands over IS the deliverable

    step 1 already caught the gone and merged branches; this step exists for the ones
    `git branch --merged` cannot see, since a rebased branch reads merged = no forever

    read `merged = yes OR absorbed = yes` as "safe"; only `merged = no AND absorbed = no`
    is real unmerged work

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
    - the deny list and `pretooluse.sh` both refuse these commands, which is the design rather
      than an obstacle to work around: they are the user's to run, never the agent's

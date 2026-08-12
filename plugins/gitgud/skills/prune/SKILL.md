---
name: prune
model: opus
effort: high
license: MIT
compatibility: requires bash, git
description: prune the dead tracking refs, report the trunk delta, then hand back every merged branch delete command
disable-model-invocation: true
metadata:
  kind: trigger
---
**one sweep for every ref already spent:** merged branches named, unmerged left alone
- prunes dead tracking refs, then reports the trunk delta
- preserves unmerged branches and names only the merged ones
- deletes nothing; every deletion is handed back as a command you run

# Instructions

## Telemetry
```!
"${CLAUDE_PLUGIN_ROOT}"/skills/prune/prune.sh
echo "sidecar exit: $?"
```
- it already ran, so there is no command to issue
- fail (`sidecar exit` > 0) → abort and report: "<raw terminal error>"
- success (`sidecar exit` = 0) → report "/gitgud:prune telemetry" and continue to step 1

1. run the native shell command exactly as specified
  ```bash
  plugins/gitgud/shared/triage.sh
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

## Output Style
```!
awk 'NR>1 && /^---$/ {p=1; next} p' "${CLAUDE_PLUGIN_ROOT}/output-styles/operator.md"
```

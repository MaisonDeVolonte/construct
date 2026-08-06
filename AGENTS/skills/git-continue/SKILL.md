---
name: git-continue
description: Measure the trunk delta, then run the sync it planned against four narrow allows.
disallowed-tools: Write Edit
disable-model-invocation: true
metadata:
  kind: trigger
---
```javascript
/**
 * ======================================================
 * @file SKILL.md - trunk sync handover trigger
 * ======================================================
 * @description
 * - ran only on explicit `@git-continue` command
 * - measures the trunk delta, then runs the sync it planned
 * - runs `AGENTS/skills/git-continue/git-continue.sh`, whose only write is a fetch of remote-tracking refs
 * - the sidecar stays read-only; the four sync forms are narrow allows the trigger runs itself
 * - separates ahead from behind, since a behind trunk fast-forwards and never needs @git-fresh
 * @see AGENTS.md, AGENTS/skills/check-skills/SKILL.md, AGENTS/skills/git-continue/git-continue.sh, AGENTS/shared/handover.sh
 */
```

**@git-continue:** Run ONLY on explicit `@git-continue` command
- run to pause work, sync the trunk, and resume where you left off
- enforces trunk-based development: the sync always ends on the trunk, never a feature branch
- the sidecar measures and plans; the trigger runs it, and a diverged trunk is still handed over

## telemetry

```!
"${CLAUDE_PLUGIN_ROOT}"/skills/git-continue/git-continue.sh
echo "sidecar exit: $?"
```

1. read the block above; it already ran, so there is no command to issue
  - fail (`sidecar exit` > 0) → abort and report: "<raw terminal error>"
  - success (`sidecar exit` = 0) → continue to step 2

2. report the telemetry, then act on `sync state`, since it decides which shape applies
    - `up to date` → say so; there is nothing to run
    - `behind, fast-forwards cleanly` → run the emitted commands, each as its own tool call
    - `diverged` → STOP and hand the block over; local commits origin lacks need a rebase or a
      merge commit, and both rewrite history, so both stay the user's call

3. run the sequence, one command per tool call, in the printed order
- STOP at the first non-zero exit and report the raw error; never improvise a recovery
- a conflicted `git stash pop` leaves the stash entry intact, so say so and let the user resolve it
- close by reporting the new state: branch, ahead/behind, and whether the tree came back dirty

    The floor allows this trigger four forms: `git stash push -u -m 'auto-stash: @git-continue'`,
    `git switch main|master`, `git merge --ff-only origin/main|master`, and `git stash pop`.
    Anything the sidecar prints beyond those is handed over, never reshaped to fit through the gate.

    The branch names are literal because settings.json cannot read the trunk the sidecar resolved.
    A repo whose trunk is neither prompts instead of running, which is the safe direction: approve
    it once for that repo, or add the name to the allow in both project and user scope.

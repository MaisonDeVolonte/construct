```javascript
/**
 * ======================================================
 * @file gitcontinue.md - trunk sync handover trigger
 * ======================================================
 * @description
 * - ran only on explicit `@gitcontinue` command
 * - READ-ONLY: measures the trunk delta and hands the sync commands back
 * - runs `AGENTS/git/gitcontinue.sh`, whose only write is a fetch of remote-tracking refs
 * - stash, switch and merge are denied as tool calls, so the user runs them
 * - separates ahead from behind, since a behind trunk fast-forwards and never needs @gitfresh
 * @see AGENTS.md, AGENTS/templates/git.md, AGENTS/git/gitcontinue.sh, AGENTS/git/handover.sh
 */
```

**@gitcontinue:** Run ONLY on explicit `@gitcontinue` command
- run to pause work, sync the trunk, and resume where you left off
- enforces trunk-based development: the handover always ends on the trunk, never a feature branch
- the sidecar measures and reports; every command that moves the tree is the user's to run

1. run the native shell command exactly as specified
  ```bash
  AGENTS/git/gitcontinue.sh
  ```
  - fail (exit code > 0) → abort and report: "<raw terminal error>"
  - success (exit code = 0) → continue to step 2

2. report the telemetry, then the handover, then STOP
    - read `sync state` first, since it decides which of the three shapes below applies
      - `up to date` → say so; there is nothing to paste
      - `behind, fast-forwards cleanly` → the handover is safe to run as printed
      - `diverged` → the trunk holds local commits origin lacks, so name them before anything else
    - close with one copy-paste bash block holding every handover command, in that same order

    NEVER run a stash, switch or merge, and never offer to; handing the commands over IS the
    deliverable, and the deny floor refuses all three as tool calls anyway

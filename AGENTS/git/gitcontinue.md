```javascript
/**
 * ====================================================
 * @file gitcontinue.md - safe pause-and-resume trigger
 * ====================================================
 * @description
 * - ran only on explicit `@gitcontinue` command
 * - stashes, fetches, fast-forwards, and pops to safely pause/resume work
 * - strictly enforces trunk-based dev: always ends back on `main`, never a feature branch
 * - runs `AGENTS/git/gitcontinue.sh`; a conflict (exit 1) hands resolution to the user
 * @see AGENTS.md, AGENTS/templates/git.md, AGENTS/git/gitcontinue.sh
 */
```

**@gitcontinue:** Run ONLY on explicit `@gitcontinue` command
- run to safely pause work, sync the trunk, and resume where you left off
- strictly enforces trunk-based development: always drops you back onto the trunk (`main`), never a feature branch
- gracefully handles stashing, fetching, fast-forwarding, and stash popping

1. run the native shell command exactly as specified:
  ```bash
  AGENTS/git/gitcontinue.sh
  ```
  - fail (exit code > 1) → abort and report: "<raw terminal error>"
  - conflict (exit code = 1) → report "@gitcontinue telemetry" and tell user to resolve conflicts in editor
  - success (exit code = 0) → continue and report: "@gitcontinue telemetry"

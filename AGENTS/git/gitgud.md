```javascript
/**
 * ===============================================
 * @file gitgud.md - safe stale-pr refresh trigger
 * ===============================================
 * @description
 * - ran only on explicit `@gitgud` command
 * - re-runs CI on a stale branch pr against the current default branch
 * - typically used after `@gitdeliver` fails to atomicize prs correctly
 * - `--watch` flag waits for the fresh CI run to complete before exiting
 * @see AGENTS.md, AGENTS/templates/git.md, AGENTS/git/gitgud.sh
 */
```

**@gitgud:** Run ONLY on explicit `@gitgud` command
- run on a stale branch pr that needs CI to re-run against the current default branch
- typically ran after @gitdeliver fails to atomicize prs correctly

**FLAGS:**
- `--watch`: use to wait for the fresh ci run to complete before exiting

1. run the native shell command exactly as specified
  ```bash
  AGENTS/git/gitgud.sh
  ```
  - fail (exit code > 0) → abort and report: "<raw terminal error>"
  - success (exit code = 0) → continue and report: "@gitgud telemetry"

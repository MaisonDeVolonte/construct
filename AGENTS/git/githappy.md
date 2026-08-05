```javascript
/**
 * ===================================
 * @file githappy.md - release trigger
 * ===================================
 * @description
 * - ran only on explicit `@githappy` command; aborts on any failed preflight check
 * - READ-ONLY: `AGENTS/git/githappy.sh` verifies every precondition and hands the sequence over
 * - the bump, both pushes, the promotion merge and the release call are all the user's to run
 * - `--minor`/`--major` (default minor) only decides the version the handover names
 * - the release api call comes last, since the tag has to reach origin before it resolves
 * @see AGENTS.md, AGENTS/templates/git.md, AGENTS/git/githappy.sh, .github/workflows/deploy.yml
 */
```

**@githappy:** Run ONLY on explicit `@githappy` command
- run when you want to release a new minor or major version
- aborts if any preflight fails: dirty tree, detached HEAD, out-of-sync trunk, missing production
- computes the next version from `package.json` rather than applying it, since `npm version` commits
- the handover bumps, pushes `main` with tags, fast-forwards `production`, pushes, and publishes
- `deploy.yml` listens for the `production` push and triggers live deployment
- releases nothing itself; every step is handed over for you to run

**FLAGS:**
- `--minor`: used for new features or bug fixes (default)
- `--major`: used for breaking changes or major updates

1. run the native shell command exactly as specified
  ```bash
  AGENTS/git/githappy.sh <flag>
  ```
  - fail (exit code > 0) → abort and report: "<raw terminal error>"
  - success (exit code = 0) → continue to step 2

2. report the telemetry, then the handover, then STOP
    - confirm `current version` and `next version` read the way the user expects before anything
    - `commits promoting to production` is what the release actually ships; name it
    - close with one copy-paste bash block holding every handover command, in that same order

    NEVER run the bump, a push, the merge or the release call, and never offer to; handing the
    sequence over IS the deliverable

    - the release call is the last line and only resolves after the tag push above it lands
    - github's git endpoints take only basic auth, which base64s the masked sentinel past the
      proxy, so a push needs the user's tty and cannot work from a sandboxed command

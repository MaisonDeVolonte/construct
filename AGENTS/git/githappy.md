```javascript
/**
 * ===================================
 * @file githappy.md - release trigger
 * ===================================
 * @description
 * - ran only on explicit `@githappy` command; aborts on any failed preflight check or
 *   uncommitted changes on `main`
 * - `--minor`/`--major` (default minor) bumps `package.json`, commits, and tags locally
 *   on `main`
 * - fast-forwards `production` to `main` and pushes, triggering `deploy.yml`'s live deployment
 * - syncs `main` back to `origin` and generates a github release page with release notes
 * @see AGENTS.md, AGENTS/templates/git.md, AGENTS/git/githappy.sh, .github/workflows/deploy.yml
 */
```

**@githappy:** Run ONLY on explicit `@githappy` command
- run when you want to release a new minor or major version 
- aborts if any preflight checks fail, including uncommitted changes on `main`
- `npm version --flag` updates version in `package.json` and creates a `commit` and adds a `tag` locally on `main`
- switches to local `production` branch, fast-forwards to match local `main`, and pushes to `origin` 
- `deploy.yml` listens for the `production` branch push and triggers live deployment
- switches back to `main` and pushes to `origin` so both branches are identical
- generates a github release page with auto-generated release notes

**FLAGS:**
- `--minor`: used for new features or bug fixes (default)
- `--major`: used for breaking changes or major updates

1. run the native shell command exactly as specified
  ```bash
  AGENTS/git/githappy.sh <flag>
  ```
  - fail (exit code > 0) → abort and report: "<raw terminal error>"
  - success (exit code = 0) → report completion and share the github release url

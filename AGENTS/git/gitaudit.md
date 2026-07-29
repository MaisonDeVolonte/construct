```javascript
/**
 * =====================================================
 * @file gitaudit.md - read-only git diagnostics trigger
 * =====================================================
 * @description
 * - ran only on explicit `@gitaudit` command; read-only, never mutates tracked files
 * - runs `AGENTS/git/gitaudit.sh` then evaluates telemetry for ghost branches, local
 *   clutter, conflict risk, and a dirty trunk
 * - outputs a numbered list of issues with manual + `@agent` shortcut resolutions
 * - appends that report to `docs/audits/YYYY-MM-DD.md`, one file per day, many audits per file
 * @see AGENTS.md, AGENTS/templates/git.md, AGENTS/git/gitaudit.sh, AGENTS/templates/audits.md, docs/audits/
 */
```

**@gitaudit:** Run ONLY on explicit `@gitaudit` command
1. run the native shell command exactly as specified
  ```bash
  AGENTS/git/gitaudit.sh
  ```

2. IF FAILURE (exit code > 0):
  ```text
  - output the raw terminal error inside a markdown code block
  ```

3. IF SUCCESS (exit code = 0):
  - evaluate the telemetry against these potential scenarios:
    - IF a branch has `upstream: gone`: Explicitly label it a "Ghost Branch"
    - IF a branch has `merged: yes` and `upstream: none`: Explicitly label it "Local Clutter"
    - IF `conflict_risk_files` > 0: Immediately issue a high-alert warning naming the branch
    - IF there are `unstaged_files` or `untracked_files` on the default branch: help the user clear the working directory

  ```text
  - output the raw telemetry

  - provide a highly specific summary of how/why the repository might be in its current state
  - generate a numbered list of potential issues/tasks (e.g. ghost branches, conflict risk, etc)
  - include specific/explicit resolution steps (both manual terminal commands and @agent shortcuts where possible)
  ```

4. THEN append the same report to the audit file (see `AGENTS/templates/audits.md`)
  ```text
  - the sidecar already seeded the file; take the target from the `--- audit ---` telemetry:
    - `audit_file` is the path, `audit_time` is the heading timestamp
    - `audit_count` is how many audits the file already holds, so this one is #(audit_count + 1)
  - append a new `## Audit #N: YYYY-MM-DD HH:MM` section, never overwrite an earlier audit
  - write the report as delivered to the user, minus the raw telemetry dump
  ```

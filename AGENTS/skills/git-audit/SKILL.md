---
name: git-audit
description: Read-only git diagnostics: branch triage, team probes, and a dated audit saved to file.
disable-model-invocation: true
metadata:
  kind: trigger
---
```javascript
/**
 * =====================================================
 * @file SKILL.md - read-only git diagnostics trigger
 * =====================================================
 * @description
 * - ran only on explicit `@git-audit` command; read-only, never mutates tracked files
 * - runs `AGENTS/skills/git-audit/git-audit.sh` then evaluates telemetry for ghost branches, local
 *   clutter, conflict risk, and a dirty trunk
 * - outputs a numbered list of issues with manual + `@agent` shortcut resolutions
 * - appends that report to `docs/audits/YYYY-MM-DD.md`, one file per day, many audits per file
 * @see AGENTS.md, AGENTS/skills/check-skills/SKILL.md, AGENTS/skills/git-audit/git-audit.sh, AGENTS/skills/doc-audits/SKILL.md, docs/audits/
 */
```

**@git-audit:** Run ONLY on explicit `@git-audit` command
## telemetry

```!
"${CLAUDE_PLUGIN_ROOT}"/skills/git-audit/git-audit.sh
echo "sidecar exit: $?"
```

1. read the block above; it already ran, so there is no command to issue

2. IF FAILURE (exit code > 0):
  ```text
  - output the raw terminal error inside a markdown code block
  ```

3. IF SUCCESS (exit code = 0):
  - evaluate the telemetry against these potential scenarios:
    - IF a branch has `upstream: gone`: Explicitly label it a "Ghost Branch"
    - IF a branch has `merged: yes` and `upstream: none`: Explicitly label it "Local Clutter"
    - IF a branch has `absorbed: yes` and `merged: no`: Explicitly label it "Rebase Absorbed"
    - IF `conflict_risk_files` > 0: Immediately issue a high-alert warning naming the branch
    - IF there are `unstaged_files` or `untracked_files` on the default branch: help the user clear the working directory

  - `merged` vs `absorbed`, and why only one of them answers "is anything lost by deleting this":
    - `merged` comes from `git cherry`, which compares patch-ids, so a branch whose work reached
      the trunk by rebase or squash reads `merged: no` forever, however long ago it landed
    - `absorbed` compares trees: `yes` means the branch tip adds NOTHING the trunk lacks
    - treat `absorbed: yes` as safe to delete regardless of what `merged` says
    - only `absorbed: no` AND `merged: no` is real unmerged work; never propose deleting it

  ```text
  - output the raw telemetry

  - provide a highly specific summary of how/why the repository might be in its current state
  - generate a numbered list of potential issues/tasks (e.g. ghost branches, conflict risk, etc)
  - include specific/explicit resolution steps (both manual terminal commands and @agent shortcuts where possible)
  ```

4. THEN append the same report to the audit file (see `AGENTS/skills/doc-audits/SKILL.md`)
  ```text
  - the sidecar reports the target but never creates it; take it from `--- audit ---`:
  - CREATE the file first if it does not exist, with `# <audit_file>` as its only line
    - `audit_file` is the path, `audit_time` is the heading timestamp
    - `audit_count` is how many audits the file already holds, so this one is #(audit_count + 1)
  - append a new `## Git Audit #N: YYYY-MM-DD HH:MM` section, never overwrite an earlier audit
  - write the report as delivered to the user, in the four subsections audits.md defines
    - `state` and `findings` are hyphen bullets, one clause each
    - `resolutions` are checkboxes, one per finding, in the same order
    - `telemetry` closes the entry with the raw output, fenced and unedited
  ```

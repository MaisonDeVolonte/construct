---
name: git-gud
description: Re-run CI on a stale branch PR against the current default branch, after @git-deliver leaves a PR computed against a trunk that has since moved.
argument-hint: [--watch]
disable-model-invocation: true
metadata:
  kind: trigger
---
**/git-gud:** the frontmatter blocks every path except an explicit invocation
- run on a stale branch pr that needs CI to re-run against the current default branch
- typically ran after `/git-deliver` fails to atomicize prs correctly

## telemetry

```!
"${CLAUDE_PLUGIN_ROOT}"/skills/git-gud/git-gud.sh
echo "sidecar exit: $?"
```

1. read the block above; it already ran, so there is no command to issue
  - `sidecar exit` > 0 → abort and report the raw terminal error inside a markdown code block
  - `sidecar exit` = 0 → report the telemetry verbatim, then continue

2. IF `--watch` was passed, run the native shell command exactly as specified
  ```bash
  AGENTS/skills/git-gud/git-gud.sh --watch
  ```
  - this one is a tool call, so the floor and the hook both see it
  - report the raw terminal error on failure, the fresh run's conclusion on success

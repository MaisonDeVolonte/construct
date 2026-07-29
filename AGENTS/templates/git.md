```javascript
/**
 * ======================================
 * @file git.md - git automation template
 * ======================================
 * @description
 * - ran only on explicit `@gitautomation` commands
 * - starts with a native shell script sidecar
 * - fail: outputs raw terminal errors
 * - success: evaluates telemetry and executes subsequent actions
 * @see AGENTS.md, /AGENTS/git/
 */
```

# @gitautomation
All @gitautomations follow the following general shape:

1. run the native shell command exactly as specified
  ```bash
  AGENTS/gitautomation.sh
  ```

2. IF FAILURE (exit code > 0):
  ```text
  - output the raw terminal error inside a markdown code block
  ```

3. IF SUCCESS (exit code = 0):
  - evaluate the telemetry against these potential scenarios:
    - IF ...
    - IF ...

  ```text
  - output the raw telemetry

  - provide ...
  - generate ...
  - include ...
  ```

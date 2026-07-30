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
 * - `AGENTS/templates/git.sh` validates every trigger doc and sidecar pair against the rules above
 * @see AGENTS.md, AGENTS/templates/git.sh, /AGENTS/git/
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

```text
VERIFY - not part of the trigger
- RUN `AGENTS/templates/git.sh` after touching a trigger doc or its sidecar; pass a path to scope it
- FIX every ERROR, since each one breaks a rule stated in the header above
- STOP on a `secret` finding and ask the user before truncating it; the key needs rotating first
- JUSTIFY or fix every WARN; the sidecar tolerates them, the next reader may not
- ANSWER the checklist it prints, since those rules are the ones no script can judge
```

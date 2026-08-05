```javascript
/**
 * ======================================
 * @file git.md - git automation template
 * ======================================
 * @description
 * - ran only on explicit `@gitautomation` commands
 * - starts with a native shell script sidecar, which measures and never mutates
 * - every sidecar sources `AGENTS/git/handover.sh`, so the whole family shares one output shape
 * - fail: outputs raw terminal errors
 * - success: reports the telemetry, then fences the handover for the user to paste
 * - the only template whose sidecar scans `AGENTS/git/`, not a `docs/` artifact directory
 * - `AGENTS/templates/git.sh` validates every trigger doc and sidecar pair against the rules above
 * @see AGENTS.md, AGENTS/templates/git.sh, AGENTS/git/handover.sh, /AGENTS/git/
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

## the two blocks
every sidecar prints the same pair, in the same order, so each trigger doc reads one contract:

```text
=== @gitname telemetry ===
key: value

=== @gitname handover ===
# a note explaining the block, or why it is empty
git command one
git command two
=====================
```

- `telemetry` is what was measured; the trigger doc branches on it
- `handover` is what the user runs; every line is runnable as written, notes stay commented
- a sidecar that needs to mutate emits the command instead of running it
- close every trigger with ONE copy-paste bash block holding the handover, in that same order

## the read-only contract
- a sidecar may fetch, since that moves only remote-tracking refs, and may call the github api
- a sidecar may NOT stash, switch, merge, push, reset, restore, clean, or delete a branch
- a sidecar's commands are not tool calls, so neither the deny floor nor the hook ever sees them
- that is the whole reason for the rule: a sidecar running them was a silent bypass of both gates
- where a trigger genuinely needs to mutate, the floor opens a narrow allow and the TRIGGER runs it,
  which keeps the command in front of the gate — `@gitcontinue` and its four sync forms are the case
- `AGENTS/git/handover.sh` carries the shared preflights, queries, and block emitters
- default branch resolution goes through `git_default_branch`, since `symbolic-ref` is denied

```text
VERIFY - not part of the trigger
- RUN `AGENTS/templates/git.sh` after touching a trigger doc or its sidecar; pass a path to scope it
- FIX every ERROR, since each one breaks a rule stated in the header above
- STOP on a `secret` finding and ask the user before truncating it; the key needs rotating first
- JUSTIFY or fix every WARN; the sidecar tolerates them, the next reader may not
- ANSWER the checklist it prints, since those rules are the ones no script can judge
```

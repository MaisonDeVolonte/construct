---
name: test-scopes
description: Map every workflow script against the merged settings stack, separating what a permission rule sees from what a script runs internally, where only the sandbox is still watching.
argument-hint: "[--repo <name>] [--strict]"
disable-model-invocation: true
metadata:
  kind: trigger
---
**/test-scopes:** the frontmatter blocks every path except an explicit invocation
- answers the question the floor cannot: what does a sidecar reach once it is already running
- a permission rule sees `bash AGENTS/skills/git-fresh/git-fresh.sh` and nothing inside it
- `/test-settings` wraps this, so run it directly when you want the per-script detail

## telemetry

```!
"${CLAUDE_PLUGIN_ROOT}"/skills/test-scopes/test-scopes.sh
echo "sidecar exit: $?"
```

1. read the block above; it already ran, so there is no command to issue
  - fail (`sidecar exit` > 0) → findings exist; report them and continue to step 2
  - success (`sidecar exit` = 0) → report the clean map and continue to step 2
  - it takes minutes rather than seconds; if the block is empty the run was cut short, so say
    so plainly rather than reporting a clean pass it never reached
  - `--repo <name>` tests another repo's stack and `--strict` promotes warnings, both by tool call

2. read the two tiers differently, because they answer different questions
  - tier 1 is what the permission layer judges: one string, the invocation itself
  - tier 2 is everything that string then runs, which no allow or deny rule is ever shown
  - a `bypass` is the finding that matters: an internal command that a deny WOULD have refused,
    reached anyway because a script's commands are not tool calls
  - that is by design rather than a defect, which is exactly why it needs listing: the deny floor
    and the hook both stop at the script boundary, and only the sandbox goes further

3. report inline, then STOP

    NEVER edit a settings file or a sidecar to fix a finding, and never offer to

    - a bypass is resolved by moving the command into the trigger where the gate sees it, or by
      accepting it in writing; silently leaving it is the one option that rots
    - the read-only contract is what keeps this list short, so a sidecar that grew a mutation is
      the finding, not the rule that failed to catch it

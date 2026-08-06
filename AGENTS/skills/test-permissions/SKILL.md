---
name: test-permissions
description: Replay the labelled command corpus through the real PreToolUse hook, then audit the merged permission rules for drift, dead rules and wildcards that auto-approve.
argument-hint: [--strict]
disable-model-invocation: true
metadata:
  kind: trigger
---
**/test-permissions:** the frontmatter blocks every path except an explicit invocation
- answers one question: does the gate actually refuse what the corpus says it must refuse
- a config can read perfectly and still have a dead hook, which only a replay catches
- `/test-settings` wraps this, so run it directly when you want the detail rather than the count

## telemetry

```!
"${CLAUDE_PLUGIN_ROOT}"/skills/test-permissions/test-permissions.sh
echo "sidecar exit: $?"
```

1. read the block above; it already ran, so there is no command to issue
  - fail (`sidecar exit` > 0) → findings exist; report them and continue to step 2
  - success (`sidecar exit` = 0) → report the clean replay and continue to step 2
  - `--strict` promotes warnings to errors, and needs a tool call since the block takes no arguments

2. read the two tiers differently, because they carry different weight
  - a tier 1 failure is measured, not inferred: the hook was fed that exact string and answered
    wrongly. an effect labelled `hook` that came back silent is a hole in the guard
  - an effect labelled `none` that came back denied is over-blocking, which costs real work
  - a tier 2 finding is structural: it reports what the files literally say, never what the
    matcher would do, so read it as a lead rather than a verdict
  - `no deny rule names X, and an allow wildcard covers it` is the one to act on first: that
    command is auto-approved today with no prompt at all

3. report inline, then STOP

    NEVER edit a settings file to fix a finding, and never offer to; the audit is the deliverable

    - every repair belongs in the scope its `.md` names, and is the user's to apply
    - a corpus gap is itself a finding: add the spelling you found in the wild, since coverage
      is the whole point of keeping a labelled list

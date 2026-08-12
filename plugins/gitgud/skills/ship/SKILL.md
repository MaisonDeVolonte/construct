---
name: ship
model: opus
effort: max
license: MIT
compatibility: requires bash, jq, curl, git
description: verify every release precondition, abort on any fault, then hand back the bump, push and promote steps
disable-model-invocation: true
metadata:
  kind: trigger
---
**abort beats a bad bump:** every release precondition checked before the version moves
- aborts on a dirty tree, detached HEAD, stale trunk or missing production
- computes the next version rather than applying it, since `npm version` commits
- releases nothing; the bump, push and promote are handed over

# Instructions

## Telemetry
```!
"${CLAUDE_PLUGIN_ROOT}"/skills/ship/ship.sh $ARGUMENTS
echo "sidecar exit: $?"
```
- it already ran, so there is no command to issue
- fail (`sidecar exit` > 0) → abort and report: "<raw terminal error>"
- success (`sidecar exit` = 0) → continue to step 1

1. report the telemetry, then the handover, then STOP
    - confirm `current version` and `next version` read the way the user expects before anything
    - the bump follows the flag: `--minor` (default) covers features and fixes, `--major` breaking changes
    - `commits promoting to production` is what the release actually ships; name it
    - close with one copy-paste bash block holding every handover command, in that same order

    NEVER run the bump, a push, the merge or the release call, and never offer to; handing the
    sequence over IS the deliverable

    - the release call is the last line and only resolves after the tag push above it lands
    - github's git endpoints take only basic auth, which base64s the masked sentinel past the
      proxy, so a push needs the user's tty and cannot work from a sandboxed command

## Output Style
```!
awk 'NR>1 && /^---$/ {p=1; next} p' "${CLAUDE_PLUGIN_ROOT}/output-styles/operator.md"
```

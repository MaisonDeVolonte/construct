---
name: ship
model: opus
effort: max
license: MIT
compatibility: requires bash, jq, curl, git
description: verify every release precondition, abort on any fault, then hand back the bump, push and promote steps
argument-hint: "[--help] [--test]"
disable-model-invocation: true
---

# Instructions

## Telemetry
```!
"${CLAUDE_PLUGIN_ROOT}"/skills/audit/audit.sh $ARGUMENTS
echo "audit exit: $?"
"${CLAUDE_PLUGIN_ROOT}"/skills/ship/ship.sh $ARGUMENTS
echo "sidecar exit: $?"
```
- `help: requested` → the run was refused before it started; `## Help` below is the whole turn
- BOTH sidecars already ran, the audit first, so there is no command to issue
- a release is the one moment a whole-repo read is worth its cost, which is why the audit chains here
- a red row in the audit ABORTS the release; report it and stop, since a bump cannot fix composition
- fail (`audit exit` > 0 or `sidecar exit` > 0) → abort and report: "<raw terminal error>"
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

## Help
> IF the invocation carries `--help` or `-h`, this section is the whole turn:

```text
SKILL: /plugin:name
DESCRIPTION: <the `description` frontmatter, verbatim>
POSTURE: <the readme index's keyword for this skill>
FLAGS:
- --flag: <what it changes, in the telemetry bullet's own words>
ARGUMENTS:
- <arg>: <what it names>
ARTIFACT: <the `metadata.artifact` path, or none>
OUTPUT: <what lands in the turn: an audit entry, a handover block, an inline report>
SPEC: <this doc's own path>
```

- every field prints, in this order; one with nothing to say prints `none`
- every value is COPIED from the source named beside it, never composed fresh
- ask what they are actually trying to do, and what they have already tried
- name the flag or the sibling skill that fits their answer, then STOP
- run no step, write no file, and never fall through to step 1

## Subagent Style
```!
awk 'NR>1 && /^---$/ {p=1; next} p' "${CLAUDE_PLUGIN_ROOT}/subagent-styles/operator.md"
```

---
name: rerun
model: opus
effort: high
license: MIT
compatibility: requires bash, jq, curl, git
description: merge the current default branch into a stale PR so its CI re-runs against a trunk that has since moved
argument-hint: "[--help] [--watch]"
disable-model-invocation: true
metadata:
  kind: trigger
---
**stale PRs catch up to the trunk:** merge in what moved and CI runs again
- merges the current default branch into the stale branch PR
- typically after `/gitgud:deliver` leaves a PR computed against old trunk
- `--watch` follows the run instead of returning immediately

# Instructions

## Telemetry
```!
"${CLAUDE_PLUGIN_ROOT}"/skills/rerun/rerun.sh $ARGUMENTS
echo "sidecar exit: $?"
```
- `help: requested` → the run was refused before it started; `## Help` below is the whole turn
- it already ran, so there is no command to issue
- `sidecar exit` > 0 → abort and report the raw terminal error inside a markdown code block
- `sidecar exit` = 0 → report the telemetry verbatim, then continue

1. IF `--watch` was passed, run the native shell command exactly as specified
  ```bash
  plugins/gitgud/skills/rerun/rerun.sh --watch
  ```
  - this one is a tool call, so the floor and the hook both see it
  - report the raw terminal error on failure, the fresh run's conclusion on success

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

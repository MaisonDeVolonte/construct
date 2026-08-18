---
name: continue
model: opus
effort: high
license: MIT
compatibility: requires bash, git
description: snapshot, then measure the trunk delta, then run the sync against four narrow allows
argument-hint: "[--help] [--test]"
disable-model-invocation: true
metadata:
  artifact: .construct/gitgud/continue/
---

# Instructions

## Telemetry
```!
"${CLAUDE_PLUGIN_ROOT}"/skills/backup/backup.sh
echo "backup exit: $?"
"${CLAUDE_PLUGIN_ROOT}"/skills/continue/continue.sh $ARGUMENTS
echo "sidecar exit: $?"
```
- `help: requested` → the run was refused before it started; `## Help` below is the whole turn
- it already ran, so there is no command to issue
- fail (`backup exit` > 0 or `sidecar exit` > 0) → abort and report: "<raw terminal error>"
- success (`sidecar exit` = 0) → continue to step 1

1. report the telemetry, then act on `sync state`, since it decides which shape applies
    - `up to date` → say so; there is nothing to run
    - `behind, fast-forwards cleanly` → run the emitted commands, each as its own tool call
    - `behind, but the sync is yours to run` → STOP and hand the block over; either the incoming
      commits or your own dirty tree write a path the sandbox denies, and a sandboxed merge
      half-applies rather than refusing, leaving the writable files checked out against a HEAD
      that never moved
    - `colliding, the sync is yours to run` → STOP and hand the block over; a path is both
      incoming and locally uncommitted at once, and a merge would write it before stash pop got
      a chance to restore yours, so the collision is the user's to resolve, never a script's guess
    - `diverged` → STOP and hand the block over; local commits origin lacks need a rebase or a
      merge commit, and both rewrite history, so both stay the user's call
- name the artifact path from the telemetry, so the user can read the full manifest later

2. run the sequence, one command per tool call, in the printed order
- STOP at the first non-zero exit and report the raw error; never improvise a recovery
- a conflicted `git stash pop` leaves the stash entry intact, so say so and let the user resolve it
- close by reporting the new state: branch, ahead/behind, and whether the tree came back dirty

    The floor allows this trigger four forms: `git stash push -u -m 'auto-stash: /gitgud:continue'`,
    `git switch main|master`, `git merge --ff-only origin/main|master`, and `git stash pop`.
    Anything the sidecar prints beyond those is handed over, never reshaped to fit through the gate.

    The branch names are literal because settings.json cannot read the trunk the sidecar resolved.
    A repo whose trunk is neither prompts instead of running, which is the safe direction: approve
    it once for that repo, or add the name to the allow in both project and user scope.

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

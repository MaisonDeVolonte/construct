---
name: scopes
description: Map every workflow script against the merged settings stack, separating what a permission rule sees from what a script runs internally, where only the sandbox is still watching.
argument-hint: "[--repo <name>] [--strict]"
disable-model-invocation: true
metadata:
  kind: trigger
---
**/operator:scopes:** the frontmatter blocks every path except an explicit invocation
- answers the question the floor cannot: what does a sidecar reach once it is already running
- a permission rule sees `bash plugins/gitgud/skills/nuke/nuke.sh` and nothing inside it
- `/operator:settings` wraps this, so run it directly when you want the per-script detail

## telemetry

```!
"${CLAUDE_PLUGIN_ROOT}"/skills/scopes/scopes.sh
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

3. report inline
4. append one entry to `[audit_file]`, in the shape defined under `## the shape` below
  - the heading reads `## Scopes Audit #[next_audit]: [timestamp]`, both from the telemetry
  - `state` is what the run measured, as hyphen bullets, one clause each
  - `findings` lead with the label the sidecar printed, one bullet each, naming what it hit
  - `resolutions` are checkboxes, one per finding, in the same order
  - `telemetry` is the sidecar's whole output, fenced and unedited, pasted last
  - CREATE the file first if it does not exist, with `# <audit_file>` as its only line

5. STOP

    NEVER edit a settings file or a sidecar to fix a finding, and never offer to

    - a bypass is resolved by moving the command into the trigger where the gate sees it, or by
      accepting it in writing; silently leaving it is the one option that rots
    - the read-only contract is what keeps this list short, so a sidecar that grew a mutation is
      the finding, not the rule that failed to catch it

## the shape
> the artifact this skill appends to; the sidecar grades what landed on its next run

# .operator/scopes/YYYY-MM-DD.md
one file per day, appended to by every deliberate run:

- the heading reads `## Scopes Audit #[next_audit]: [timestamp]`, both from the telemetry
- an audit captures the boundary at a moment in time, so it is never edited after the fact
- carry an unresolved finding forward by restating it, never by editing the older audit
- lines are hyphen bullets holding a single clause, capped at 100 characters
- scrub client names, tokens, and other sensitive detail before it lands in a commit

## Scopes Audit #1: YYYY-MM-DD HH:MM

### state
the counts as hyphen bullets: scripts read, invocations by verdict, internals seen, errors, warnings

*example:*
> - 32 scripts read against a 4 file stack, none of them executed
> - 30 invocations allowed, 2 prompting and 0 refused, so the family runs unattended
> - 8062 internal commands inspected, 11 of which cross a boundary the invocation never showed

### findings
one bullet per issue, leading with the label the sidecar printed

| label | what it found |
|---|---|
| `settings` | a file in the stack that does not parse as json, so its rules never load |
| `invocation` | tier 1: the script itself is blocked, denied, or prompts on every run |
| `bypass` | tier 2: a deny names this command, but an internal call is not a tool call |
| `excluded` | it runs unsandboxed via `excludedCommands`, leaving the hook as the only gate |
| `domain` | it reaches a host absent from `allowedDomains` |
| `filesystem` | it writes outside cwd, to a path absent from `allowWrite` |
| `read` | it reads a path `denyRead` blocks for sandboxed bash |
| `missing` | a target named in the walk that is not on disk, so it was skipped |
| `resolution_shape` `resolution_parity` | an older entry whose resolutions do not match its findings |

*example:*
> - **bypass** — `backup.sh` calls `git stash`, which `deny` names and no tool call ever carries
> - **bypass** — `credentials.sh` calls `python3`, denied as `python3 -c` and reached here anyway
> - **read** — 251 internal reads touch a path `denyRead` blocks, concentrated in the probes

### resolutions
one checkbox per finding, in the same order, naming the rule and the scope file it belongs in

*example:*
> - [ ] accept the `backup.sh` stash in writing, or move it into the trigger where the gate sees it
> - [ ] narrow the `python3` deny to the `-c` form, since the sidecars call the interpreter plainly
> - [ ] add the probe read paths to `sandbox.filesystem.denyRead` exemptions in `settings.user.json`

### telemetry
the sidecar's whole output, fenced and unedited, so every claim above can be checked against it

*example:*
> ```text
> === scopes.sh workflow tester ===
> scripts: 32
> invocations: 30 allowed, 2 prompting, 0 refused
> internals: 8062 inspected, 11 of which cross a permission gate
> errors: 11
> warnings: 310
> ```

## Scopes Audit #2: repeat the above format for each deliberate run on the same day
never edit an earlier audit; a stale finding is signal about how long it went unresolved

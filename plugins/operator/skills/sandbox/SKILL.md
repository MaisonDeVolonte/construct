---
name: sandbox
description: Emit the sandbox setup this plugin cannot perform itself, resolving every template and target path on the disk it runs on, then hand the commands back for the user to run.
argument-hint: "[--local] [--project] [--user] [--managed]"
disable-model-invocation: true
metadata:
  kind: trigger
---
**/operator:sandbox:** the frontmatter blocks every path except an explicit invocation
- answers one question: which commands set this sandbox up, on this disk, for this install
- the templates ship inside the plugin, so a marketplace install holds them nowhere near the project
- reports each target's state beside its command, since a copy onto a populated scope is a merge
- emits and never applies: the deny floor stops any sidecar from writing a settings file

## telemetry

```!
"${CLAUDE_PLUGIN_ROOT}"/skills/sandbox/sandbox.sh
echo "sidecar exit: $?"
```

1. read the block above; it already ran, so there is no command to issue
  - fail (`sidecar exit` > 0) → a template is missing from the plugin; report which and STOP
  - success (`sidecar exit` = 0) → continue to step 2
  - a scope flag narrows the emit and needs a tool call, since the block above takes no arguments

2. report the emitted commands inline, in the sidecar's own order, then STOP

    NEVER run a copy yourself, and never offer to; the commands are the deliverable

    - lead with the scopes whose target is absent, since those copy clean and need no merge
    - a scope reported as populated is a merge decision, so name what is already there
    - `managed` needs sudo and lands outside the project, so it is always the reader's call
    - the credential steps are not copies; pass them through as the manual work they are
    - answer the checklist the sidecar prints, since those rules are the ones no script can judge

3. name what comes next, without running it

    - `/operator:settings` grades what landed, so it belongs after the copies rather than before
    - `/operator:credentials` proves the masking once tokens are in `~/.operator/.env`
    - `/sandbox` is the claude command that prints the merged config, and is not this skill

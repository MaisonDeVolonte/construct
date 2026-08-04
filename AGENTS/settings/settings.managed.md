# settings.managed.json
> copy to `/Library/Application Support/ClaudeCode/managed-settings.json` — mechanics live in
> [README.md](../../README.md), this file covers only why these values, in this scope

the sudo scope, kept deliberately bare. managed wins outright, so a value stated here cannot be
overridden by any scope below — which is why nothing lands here until it has run clean elsewhere.
carrying an unproven value here means a mistake costs a root edit rather than an editor.

## sandbox

`"enabled": true`
- the ceiling nothing below may lower

`"allowManagedDomainsOnly": false`
- true would honor managed's `allowedDomains` alone and discard every list below; there is no
  domain list here, so true would mean no egress at all

`filesystem.allowManagedReadPathsOnly: false`
- the same trap for reads: true honors managed `allowRead` alone, and denies still merge regardless

`filesystem.disabled: false`
- stated rather than omitted, because stating it **pins** it — no lower scope and no `--settings`
  flag can then drop the filesystem layer
- any `sandbox.filesystem` or `credentials.files` block here activates that pin
- `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB` outranks even this file

## what only this scope can do
- `allowManagedDomainsOnly` and `allowManagedReadPathsOnly`, both above
- `credentials.envVars` may use `mask`, which project and local cannot
- pinning `filesystem.disabled` against every scope below

## what must never go here, at any value
> managed wins booleans, so stating a default here pins the default too

- `allowUnsandboxedCommands` belongs in project, where an unattended repo sets it false
- `failIfUnavailable` belongs in user, where a lockout needs an editor rather than sudo

## verifying
`/sandbox` Config is the only place this file's effect shows up merged. after any promotion here,
rerun the probes — every managed key changes the merge, and the change is invisible in the file.

```javascript
/**
 * ===================================================
 * @file settings.managed.md - managed scope reasoning
 * ===================================================
 * @description
 * - pairs with settings.managed.json; sudo copy to the ClaudeCode managed path
 * - the unoverridable ceiling, kept deliberately bare; booleans stated here are pinned
 * - nothing lands here until it has run clean in user
 * @see plugins/operator/settings/settings.managed.json, plugins/operator/settings/settings.user.md, plugins/operator/skills/settings/settings.sh, AGENTS.md
 */
```

# settings.managed.json
> sudo copy to `/Library/Application Support/ClaudeCode/managed-settings.json`
- the sudo scope, kept deliberately bare
- managed wins outright: a value stated here cannot be overridden by any scope below
- an unproven value here costs a root edit rather than an editor, so everything proves out in user first

## sandbox
```json
"sandbox": {
  "enabled": true,
  "allowManagedDomainsOnly": false,
  "filesystem": {
    "allowManagedReadPathsOnly": false,
    "disabled": false
  }
}
```
- `enabled`: the ceiling nothing below may lower
- `allowManagedDomainsOnly` false: true would honor managed's domain list alone, and there is none, meaning no egress at all
- `allowManagedReadPathsOnly` false: the same trap for reads; denies still merge regardless
- `disabled` false, stated to **pin** it: no lower scope and no `--settings` flag can then drop the filesystem layer
- dropping that layer would void denyRead, credentials.files and the settings.json write protection
- any `sandbox.filesystem` or `credentials.files` block here activates the pin
- `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB` outranks even this file

## what only this scope can do
- the two allowManaged booleans above
- `credentials.envVars` may use mask, which project and local cannot
- pinning `filesystem.disabled` against every scope below

## what must never go here, at any value
> managed wins booleans, so stating a default pins the default too
- `allowUnsandboxedCommands`: belongs in project, where an unattended repo sets it false
- `failIfUnavailable`: belongs in user, where a lockout needs an editor rather than sudo

## verifying
- `/sandbox` Config is the only place this file's effect shows up merged
- rerun the probes after any promotion; every managed key changes the merge, invisibly in the file

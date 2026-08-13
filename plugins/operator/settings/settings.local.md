```javascript
/**
 * ===============================================
 * @file settings.local.md - local scope reasoning
 * ===============================================
 * @description
 * - pairs with settings.local.json; copy to .claude/settings.local.json, gitignored
 * - this repo, just you; the hooks are the real payload, the rest is restatement
 * - the drawer every 'Always Allow' click lands in
 * @see plugins/operator/settings/settings.local.json, plugins/operator/settings/settings.user.md, plugins/operator/hooks/, plugins/operator/skills/settings/settings.sh, AGENTS.md
 */
```

# settings.local.json
> copy to `.claude/settings.local.json` (gitignore it)
- gitignored, so nothing here survives a fresh clone
- the right home for a temporary grant, the wrong home for anything a collaborator needs
- ignore it everywhere at once: `**/.claude/settings.local.json` in `~/.config/git/ignore`

## sandbox
```json
"sandbox": { "enabled": true },
```
- restated so this checkout stays sandboxed on its own, with or without the scopes above it

## permissions.ask
```json
"permissions": { "ask": [ "Bash(dangerouslyDisableSandbox:true)" ] },
```
- repeated from user so the escape stays visible even in a checkout with no floor above it

## hooks
> the real payload, and the only thing that genuinely belongs in this scope
```json
"hooks": {
  "SessionStart": [{ "hooks": [
    { "type": "command", "command": "plugins/operator/hooks/sessionstart/inject-readme.sh" },
    { "type": "command", "command": "plugins/operator/hooks/sessionstart/inject-logs.sh" },
    { "type": "command", "command": "plugins/operator/hooks/sessionstart/inject-changes.sh" }
  ] }],
  "PreToolUse": [{ "matcher": "Bash", "hooks": [
    { "type": "command", "command": "plugins/operator/hooks/pretooluse/block-destructive-git.sh" },
    { "type": "command", "command": "plugins/operator/hooks/pretooluse/block-policy-edits.sh" },
    { "type": "command", "command": "plugins/operator/hooks/pretooluse/block-outside-moves.sh" }
  ] }],
  "PostToolUse": [{ "matcher": "Write|Edit", "hooks": [
    { "type": "command", "command": "plugins/operator/hooks/posttooluse/eslint.sh", "timeout": 120 },
    { "type": "command", "command": "plugins/operator/hooks/posttooluse/retardify-file.sh", "timeout": 120 },
    { "type": "command", "command": "plugins/operator/hooks/posttooluse/retardify-code.sh", "timeout": 120 }
  ] }],
  "TaskCompleted": [{ "hooks": [{ "type": "command", "command": "plugins/operator/hooks/taskcompleted/demand-log-note.sh" }] }],
  "Stop": [{ "hooks": [
    { "type": "command", "command": "plugins/operator/hooks/stop/retardify-output.sh" },
    { "type": "command", "command": "plugins/operator/hooks/stop/demand-log-synthesis.sh" }
  ] }]
}
```
- one entry per action, so registering a subset is deleting lines rather than editing a script
- `SessionStart`: the readme, the newest log threads, then the dirty tree, one payload each
- `PreToolUse`: the failover for the committed deny list, reading the whole command string
- it runs before every rule; no allow can override its block
- it blocks by exit 2, or by printing permissionDecision deny on exit 0; exit 1 lets the call through
- `PostToolUse`: eslint fixes, then file-shape and code-legibility findings, never blocking
- `TaskCompleted`: blocks the turn until the day's log is noted
- `Stop`: grades the reply's style, then demands a synthesis while the log carries pending work
- handler identity is the command string: one string in two scopes runs once, two spellings run twice

## the always-allow drawer
- every 'Always Allow' click lands here as an ordinary allow rule
- deny and ask beat allow from any scope, so a click cannot erase a gate you meant to keep
- a hook allow likewise only skips the prompt; deny and ask still apply
- bash grants persist per repo and command; edit grants expire with the session
- approving a compound command saves one rule per subcommand, up to five

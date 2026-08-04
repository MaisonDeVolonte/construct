# settings.local.json
> copy to `.claude/settings.local.json` — mechanics live in [README.md](../../README.md), this
> file covers only why these values, in this scope

gitignored, so nothing here survives a fresh clone. that makes it the right home for a temporary
grant and the wrong home for anything a collaborator needs. keep it out of git everywhere at once
with `**/.claude/settings.local.json` in `~/.config/git/ignore`, since a per-repo rule is one repo
away from being forgotten.

## sandbox

`"enabled": true`
- restated so this checkout stays sandboxed on its own, with or without the scopes above it

## permissions.ask

`Bash(dangerouslyDisableSandbox:true)`
- repeated from user so the escape stays visible even in a checkout with no floor above it

## hooks
> the real payload, and the only thing that genuinely belongs in this scope

`SessionStart` → `AGENTS/hooks/sessionstart.sh`
- injects the readme and the two most recent logs, so a session opens already briefed

`PreToolUse` → `AGENTS/hooks/pretooluse.sh`, matching `Bash`
- runs before every rule and can veto what an allow would pass
- the failover for the committed deny list, reading the whole command string rather than a
  parsed subcommand, since deny rules are prefix-anchored and a trailing flag walks past them

`PostToolUse` → `AGENTS/hooks/posttooluse.sh`, matching `Write|Edit`, 120s timeout
- lints and reports comment and wayfinder findings, never blocking

`TaskCreated` → `AGENTS/hooks/taskcreated.sh`
- nudges a new thread when a task is unrelated to the last, advisory only

`TaskCompleted` → `AGENTS/hooks/taskcompleted.sh`
- blocks the turn until the day's log is noted

`Stop` → `AGENTS/hooks/stop.sh`
- hourly: saves notes and prompts, then synthesizes the day's log

## the always-allow drawer
every `Always Allow` click lands here as an ordinary allow rule. that is fine — deny and ask both
beat allow from any scope, so a click cannot erase a gate you meant to keep. note that edit grants
expire with the session while bash grants persist per repo and command, which is why a prompt you
thought you dismissed permanently comes back tomorrow.

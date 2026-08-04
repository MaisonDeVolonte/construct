# authoring rules
> applies to every scope — mechanics live in [README.md](../../README.md), this file covers how to
> write a rule that matches what you think it matches

a permission rule is a string match, not a parser. it never sees the command the way you read it,
so every habit below exists because the obvious phrasing missed something.

## shape

- write lists most-destructive-first, for the human who reads them rather than the matcher
- one broad allow with narrow denies beats enumerating every safe subcommand
- rules match exactly, so wildcard every position a flag could occupy

## the four traps

`spaces are load-bearing`
- `Bash(ls *)` matches `ls -la` and not `lsof`
- `Bash(ls*)` matches both, including every command that merely starts with those letters

`a trailing star is what matches arguments`
- `Bash(x.sh)` misses `x.sh --flag`
- `Bash(x.sh*)` holds

`interpose a flag twin, never a bare star`
- `Bash(go * run*)` also matches `go build ./cmd/runner`, since `*` spans the subcommand
- write `Bash(go -* run*)` so the wildcard covers flags only

`a json comment voids the file`
- a single `//` line makes the whole settings file unparseable, and nothing announces it
- the scope reads as installed while contributing zero rules
- group with blank lines instead, and run `jq empty` on the file after every edit

## choosing deny or ask

- deny is for what should never run, at any prompt
- ask is for what the sandbox cannot contain, since it prompts even where auto-allow would not
- a `Read` deny is not a deny: the missing verbs only look safe, so add the Write and Edit twins
- deny beats ask beats allow, from any scope, so the strictest rule anywhere is the one that wins

`never deny a path git tracks`
- a deny is projected into the macos sandbox, so it stops every process rather than the agent alone
- git is a process: it cannot unlink through a deny, so a branch switch half-completes and strands
  the files it could not write, leaving a tree that only an unsandboxed terminal can repair
- the symptom is `unable to unlink old '<path>': Operation not permitted`, which reads as a
  filesystem fault rather than a rule you wrote
- use ask for tracked paths, which gates the agent's Write and Edit without reaching the sandbox
- keep deny for what git never touches: credentials, key material, history files, `.env`
- `pretooluse.sh` still refuses a command naming a protected path, so ask is not the only guard

## verifying

- `AGENTS/settings/permissions.sh` replays the labeled corpus against the live rules
- `AGENTS/settings/scopes.sh` maps every sidecar against the merged stack
- `@settingsaudit` wraps both and adds live probes, since a config can be perfect while the gate
  is dead
- test a candidate rule at cli scope first, so a wrong one costs a session rather than a clone
  (see [settings.cli.md](settings.cli.md))

# settings.project.json
> copy to `.claude/settings.json` — mechanics live in [README.md](../../README.md), this file
> covers only why these values, in this scope

the floor that travels. committed, so this is the only scope a clone carries, and the only reason
its 197 rules duplicate user's 193 is that **a clone may land on a machine with no floor above it**.
that one sentence is what the duplication buys; if it ever stops being true, all of it is dead weight.

each section below either mirrors user exactly or states its delta. a mirror is an assertion the
audit tests, not a shorthand — `settingsaudit.sh` diffs the section against user and fails if the
two have diverged while this file still claims they have not.

## sandbox

`"enabled": true` `"failIfUnavailable": true` `"allowUnsandboxedCommands": true`
- restated so a fresh clone is sandboxed before any managed file exists
- set `allowUnsandboxedCommands` false in any repo running unattended, which is the one value
  here that should differ per project

`"excludedCommands": []`
- empty on purpose: an exclusion unsandboxes the whole invocation rather than one binary
- gh sat here once, and the exclusion never reached the gh inside a sandboxed sidecar anyway

`network.allowedDomains` — mirrors user
- repeated so the egress list travels with the clone

**absent by design:** `credentials`, `filesystem`, `enableWeakerNetworkIsolation`
- `mask` is honored from user, managed, and cli only, so a credentials block here would be inert
- `filesystem.allowWrite` is this machine's cache layout, which the next machine does not share
- this scope cannot set `filesystem.disabled` at all

## permissions.allow
> mirrors user

## permissions.ask
> mirrors user

## permissions.deny
> mirrors user, plus the repo-shaped block below

### generated — repo paths no agent should write
`Edit(**/.git/**)` `Write(**/.git/**)`
- the object store and refs; a bad write corrupts history rather than editing it

`Edit(webflow/**)` `Write(webflow/**)`
- exported output, owned by the design tool and overwritten on the next export
- present in willwong, absent here, which is the shape of this whole block: **a clone prunes what
  it does not have, and adds what it does**

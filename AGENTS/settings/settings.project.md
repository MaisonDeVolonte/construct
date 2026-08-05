```javascript
/**
 * ===================================================
 * @file settings.project.md - project scope reasoning
 * ===================================================
 * @description
 * - pairs with settings.project.json; copy to .claude/settings.json
 * - committed, so the only scope a clone carries; mirrors user as its portable floor
 * - a mirror claim here is an assertion: settingsaudit.sh diffs it and fails on divergence
 * @see AGENTS/settings/settings.project.json, AGENTS/settings/settings.user.md, AGENTS/settings/settings.local.md, AGENTS/settings/settingsaudit.sh, AGENTS.md
 */
```

# settings.project.json
> copy to `.claude/settings.json`
- the floor that travels: committed, the only scope a clone carries
- the duplication of user buys one sentence: a clone may land on a machine with no floor above it
- if that ever stops being true, all of it is dead weight

## sandbox
```json
"sandbox": {
  "enabled": true,
  "failIfUnavailable": true,
  "allowUnsandboxedCommands": true,

  "excludedCommands": [],

  "network": {
    "allowedDomains": [
      "code.claude.com", "docs.claude.com",
      "github.com", "api.github.com",
      "registry.npmjs.org"
    ]
  }
},
```
- booleans restated so a fresh clone is sandboxed before any managed file exists
- `allowUnsandboxedCommands` is **false** here, which is what makes unattended work honest:
  the retry hatch needs someone to answer its prompt, and nobody is watching
- it is also the one setting that voids containment, since a retry runs outside the sandbox
- user keeps it true for attended sessions, and project outranks user, so this wins per repo
- `excludedCommands` stays empty: an exclusion unsandboxes the whole invocation, escaping both sandbox layers
- no managed lock exists for it, so any scope could widen it; keeping it empty here is the guard
- gh sat here once, and the exclusion never reached the gh inside a sandboxed sidecar anyway
- `allowedDomains` repeats user so the egress travels with the clone
- absent by design: `credentials`, since mask is inert outside user, managed and cli
- absent by design: `filesystem`, since allowWrite is this machine's cache layout
- absent by design: `enableWeakerNetworkIsolation`, a per-machine trade
- `filesystem.disabled` cannot be set from this scope at all

## permissions.allow
> mirrors user

## permissions.ask
> mirrors user

## permissions.deny
> mirrors user, plus the repo-shaped block below

### generated — repo paths no agent should write
```json
"Edit(**/.git/**)", "Write(**/.git/**)",
"Edit(webflow/**)", "Write(webflow/**)"
```
- stays deny despite the tracked-path rule: `.git/` is generated, never tracked
- a bad write corrupts history rather than editing it
- refusing `.git/config` is the point: `credential.helper` and `core.fsmonitor` execute shell
- `webflow/` is exported output, overwritten on the next export
- the block is repo-shaped: a clone prunes what it does not have, and adds what it does

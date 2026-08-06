```javascript
/**
 * =============================================
 * @file settings.user.md - user scope reasoning
 * =============================================
 * @description
 * - pairs with settings.user.json; copy to ~/.claude/settings.json
 * - every repo on this disk, just you; unproven values live here until promoted to managed
 * - each block quotes the json verbatim, then gives one why per line
 * - carries the keys and github mask reasoning, since user scope holds the credentials
 * - settingsaudit.sh diffs every rule here against the json, both directions
 * @see AGENTS/settings/settings.user.json, AGENTS/settings/settings.project.md, AGENTS/settings/settings.managed.md, AGENTS/settings/settings.cli.md, AGENTS/skills/test-settings/test-settings.sh, AGENTS.md
 */
```

# settings.user.json
> copy to `~/.claude/settings.json`
- the working floor for every repo on this disk
- a fix needs an editor rather than sudo, so values run clean here before promoting to managed

## sandbox
```json
"enabled": true,
"failIfUnavailable": true,
"allowUnsandboxedCommands": true,
"enableWeakerNetworkIsolation": true,
```
- `enabled`: restated so a directory that is not a repo stays sandboxed with no managed file installed
- `failIfUnavailable`: refuses to start rather than run unsandboxed; sits here so a lockout stays editable
- `allowUnsandboxedCommands`: the retry hatch for attended work; the ask below makes each escape visible
- set the hatch false in project for any repo running unattended
- `enableWeakerNetworkIsolation`: re-permits the trustd lookup go-tls needs, which is what gh fails without
- verify egress still refuses an unlisted host after enabling it

### filesystem
```json
"filesystem": {
  "allowWrite": [
    "~/.npm",
    "~/.cache",
    "~/Library/pnpm",
    "~/Library/Caches/pnpm"
  ],
  "denyRead": [
    "/Volumes",
    "~/Library/Keychains"
  ],
  "denyWrite": []
},
```
- `allowWrite`: this machine's package-manager scribble, the one block that is pure machine detail
- it misses the cache zed exports as npm_config_cache
- `denyRead`: the odd extras the permission layer does not already cover
- `denyWrite`: empty, since a write outside allowWrite already fails
- resolves by narrowest path, allow or deny
- `Read` and `Edit` permission rules also merge into this filesystem config
- a filesystem denial fails silent ('Operation not permitted'); only a domain prompts

### network
```json
"network": {
  "strictAllowlist": true,
  "tlsTerminate": {},
  "allowedDomains": [
    "code.claude.com", "docs.claude.com",
    "github.com", "api.github.com",
    "registry.npmjs.org"
  ]
}
```
- `strictAllowlist`: refuses unlisted hosts; without it the list only suppresses prompts
- `tlsTerminate`: the proxy that swaps a masked credential in; mask fails closed without it
- named hosts only, since a github wildcard reaches gist
- every repo on this disk inherits these, read or unread
- `github.com` `api.github.com`: git over https, and the api every sidecar reaches by curl
- `registry.npmjs.org`: npm and pnpm installs, matching the allowWrite caches
- `code.claude.com` `docs.claude.com`: WebFetch allows that also seed this bash allowlist, never the reverse

### credentials
> hides secrets from sandboxed bash only; the Read, Edit and Write tools need a permission rule
```json
"credentials": {
  "files": [
    { "path": "~/.aws",                   "mode": "deny" },
    { "path": "~/.bash_history",          "mode": "deny" },
    { "path": "~/.config/gcloud",         "mode": "deny" },
    { "path": "~/.gnupg",                 "mode": "deny" },
    { "path": "~/.kube",                  "mode": "deny" },
    { "path": "~/.netrc",                 "mode": "deny" },
    { "path": "~/.npmrc",                 "mode": "deny" },
    { "path": "~/.operator/.env",         "mode": "deny" },
    { "path": "~/.ssh",                   "mode": "deny" },
    { "path": "~/.zsh_history",           "mode": "deny" }
  ],
  "envVars": [
    { "name": "ANTHROPIC_API_KEY",        "mode": "deny" },
    { "name": "AWS_ACCESS_KEY_ID",        "mode": "deny" },
    { "name": "AWS_SECRET_ACCESS_KEY",    "mode": "deny" },
    { "name": "GITHUB_TOKEN",             "mode": "deny" },
    { "name": "IGCLI_SERP_KEY",           "mode": "deny" },
    { "name": "NPM_TOKEN",                "mode": "deny" },
    { "name": "npm_config_cache",         "mode": "deny" },
    { "name": "npm_config_global_prefix", "mode": "deny" },
    { "name": "npm_config_globalconfig",  "mode": "deny" },
    { "name": "npm_config_local_prefix",  "mode": "deny" },
    { "name": "npm_config_prefix",        "mode": "deny" },

    { "name": "GH_TOKEN", "mode": "mask", "injectHosts": ["api.github.com", "github.com"] }
  ]
},
```
- `files` refuses reads on a path; deny is the only mode it accepts
- `envVars` unsets a name before each sandboxed command; survives `filesystem.disabled`
- `mask` substitutes a sentinel rather than unsetting, so the tool still authenticates
- mask is honored from user, managed and cli only; the same block in project or local is inert
- a masked name must never also be denied, since deny wins in every scope
- every injectHosts entry must also sit in allowedDomains, or the mask fails closed
- an entry with an empty path or name is stripped with a warning at startup
- `~/.operator/.env` is doubled by the `.env*` permission deny, so either regression still holds
- `~/.operator` must be chmod 700 on creation; umask gives 755
- `IGCLI_SERP_KEY` came from probing the environment rather than any list
- `NPM_TOKEN` is publish-only; installs are unaffected
- `GITHUB_TOKEN` stays denied, an unrelated credential entirely

## keys
> one token per machine, named for the machine, so revoking it tells you exactly what breaks
- a fine-grained pat in `~/.operator/.env`, one export per service
- a lost laptop revokes one credential instead of every project's access
- user-owned throughout: no sudo to read, edit or rotate
- mask stops the token leaving, never stops it being spent; the pat's scope is the real limit
- adding a service is one export, plus a matching mask or deny entry
- install steps live in the README installation block

every token inherits the same layers; the axis is the layer, never the token

| layer                | what it stops                       |
|----------------------|-------------------------------------|
| `~/.operator` at 700 | every other account on the machine  |
| `Read(//**/.env*)`   | the Read tool, and sandboxed bash   |
| `credentials.files`  | sandboxed bash reading the file     |
| `pretooluse.sh`      | bash writes naming a protected path |
| `mask`               | the real value entering the sandbox |

### github
`GH_TOKEN` is masked to `api.github.com` and `github.com`; `GITHUB_TOKEN` stays denied

| operation            | sandboxed | why                                          |
|----------------------|-----------|----------------------------------------------|
| api through curl     | works     | honors the proxy ca, and Bearer is plaintext |
| api through gh       | never     | cgo verifies via the platform verifier       |
| git fetch, ls-remote | works     | libcurl honors the proxy ca                  |
| git push             | never     | basic auth base64s the sentinel out of reach |
| git push, hatch      | works     | unsandboxed commands hold the real token     |

- curl is the only client mask can serve, so it replaces gh for every api call in a sidecar
- gh fails whatever the config: no env var reaches a cgo-linked verifier
- excluding gh would unsandbox the entire command string rather than just gh
- push stays on the retry hatch by choice: dropping mask to gain it puts the real token in every sandboxed command
- `@git-deliver` hands its block to the user, so the credential never reaches an agent-run command
- verify the push, never the fetch: ls-remote succeeds on a public repo with no credential at all
- never add a dummy `credential.helper`: it turns a clean prompt into a 401 and breaks the hatch's keychain path
- `*.github.com` is avoided on purpose, since it reaches gist
- revisit only if anthropic ships a non-cgo gh, or the proxy learns to substitute inside base64
- upstream issues to watch (checked 2026-08-03):
  - [#26466](https://github.com/anthropics/claude-code/issues/26466): the liveliest go-tls thread; gh fails through the built-in proxy
  - [#77333](https://github.com/anthropics/claude-code/issues/77333): the same OSStatus -26276 measured here, reported on tahoe
  - [#82793](https://github.com/anthropics/claude-code/issues/82793): allowMachLookup unwired; enableWeakerNetworkIsolation stays the only go-tls fix
  - [#81157](https://github.com/anthropics/claude-code/issues/81157): an excludedCommands glob unsandboxes the whole invocation, matching what was measured here
  - [#82109](https://github.com/anthropics/claude-code/issues/82109): excludedCommands also skips commands inside shell loops; more reason it stays dropped
  - [#81211](https://github.com/anthropics/claude-code/issues/81211): feature ask for domain-scoped credential injection, the conversation nearest to mask
  - [#82255](https://github.com/anthropics/claude-code/issues/82255): the macos proxy drops git-over-ssh credentials; a second push path if it lands

## permissions.allow
> what an agent may do unattended; this list converges rather than grows
```json
"allow": [
  "Read", "Write", "Edit", "WebSearch",
  "Bash(AGENTS/**/*.sh*)",
],
```
- broad verbs by design: the deny floor carries the weight, and an enumerated allowlist goes stale
- `WebSearch` egresses nothing from the repo
- the sidecars run in regular-permissions mode; the `*` tail matches arguments, a bare `.sh` matched only a bare invocation

### inspection — reads and local scratch
```json
"Bash(ls)", "Bash(ls *)", "Bash(pwd)", "Bash(cd *)",
"Bash(stat *)", "Bash(file *)", "Bash(du *)", "Bash(df *)", "Bash(wc *)",
"Bash(which *)", "Bash(realpath *)", "Bash(basename *)", "Bash(dirname *)",
"Bash(cat *)", "Bash(head *)", "Bash(tail *)", "Bash(diff *)",
"Bash(grep *)", "Bash(rg *)", "Bash(find *)",
"Bash(sort *)", "Bash(uniq *)", "Bash(cut *)", "Bash(tr *)", "Bash(comm *)",
"Bash(jq *)", "Bash(echo *)", "Bash(printf *)", "Bash(date*)", "Bash(env)",
"Bash(uname *)", "Bash(whoami)", "Bash(mkdir *)", "Bash(touch *)", "Bash(cp *)",
```
- the space form is deliberate, since a spaceless ls rule would also match lsof
- bare entries exist only where a no-argument call is ordinary, as a trailing star matches empty
- `sed` and `awk` are absent on purpose: sed rewrites in place and awk has system()
- `xargs` and `tee` are absent for the same reason, and both take their payload from elsewhere
- `curl` and `wget` are absent because `-o` writes files, though the pipe-to-shell forms are denied
- `mkdir`, `touch` and `cp` are here because the sandbox already confines writes to cwd, and
  `pretooluse.sh` refuses any of them that names a protected path

### toolchain — build, typecheck, test
```json
"Bash(npm run*)", "Bash(npm test*)", "Bash(npm ls*)", "Bash(npm list*)",
"Bash(npm ci --ignore-scripts*)", "Bash(npm install --ignore-scripts*)",
"Bash(pnpm run*)", "Bash(pnpm test*)", "Bash(pnpm ls*)", "Bash(pnpm list*)",
"Bash(pnpm install --ignore-scripts*)",
"Bash(yarn run*)", "Bash(yarn test*)",
"Bash(tsc*)", "Bash(eslint*)", "Bash(prettier*)", "Bash(shellcheck *)",
"Bash(vitest*)", "Bash(jest*)", "Bash(playwright test*)",
"Bash(node *)", "Bash(python3 *)", "Bash(bash -n *)", "Bash(make *)",
```
- this tier is what makes unattended work possible; without it an agent stalls on its own test run
- the sandbox is the bound here, not the rule: each of these is contained to cwd and five domains
- `node *` and `python3 *` run a file, while `node -e` and `python -c` stay denied, and deny wins
- only the `--ignore-scripts` install forms are allowed, since a postinstall script is the
  supply-chain vector and the sandbox contains the filesystem rather than the credential
- a bare `npm install` deliberately has no rule at all, so it falls through to a prompt
- an ask rule for it would be wrong, since ask beats allow and would swallow the safe form above

### git — the reads an agent reasons with
```json
"Bash(git status*)", "Bash(git diff*)", "Bash(git log*)", "Bash(git show*)",
"Bash(git blame*)", "Bash(git grep *)", "Bash(git shortlog*)", "Bash(git range-diff*)",
"Bash(git ls-files*)", "Bash(git ls-tree*)", "Bash(git ls-remote*)", "Bash(git for-each-ref*)",
"Bash(git rev-parse*)", "Bash(git rev-list*)", "Bash(git merge-base*)", "Bash(git merge-tree*)",
"Bash(git describe*)", "Bash(git name-rev*)", "Bash(git cat-file*)",
"Bash(git diff-tree*)", "Bash(git diff-index*)", "Bash(git diff-files*)",
"Bash(git check-ignore*)", "Bash(git check-attr*)", "Bash(git count-objects*)",
"Bash(git verify-commit*)", "Bash(git verify-tag*)",

"Bash(git branch)", "Bash(git branch -a*)", "Bash(git branch -r*)", "Bash(git branch -v*)",
"Bash(git branch --list*)", "Bash(git branch --all*)", "Bash(git branch --remotes*)",
"Bash(git branch --contains*)", "Bash(git branch --merged*)", "Bash(git branch --no-merged*)",
"Bash(git branch --show-current*)",

"Bash(git tag)", "Bash(git tag -l*)", "Bash(git tag -n*)", "Bash(git tag --list*)",
"Bash(git tag --contains*)", "Bash(git tag --points-at*)",

"Bash(git remote)", "Bash(git remote -v*)", "Bash(git remote show*)", "Bash(git remote get-url*)",

"Bash(git stash list*)", "Bash(git stash show*)",
"Bash(git reflog)", "Bash(git reflog show*)",

"Bash(git fetch*)", "Bash(git version*)",

"Bash(git stash push -u -m 'auto-stash: @git-continue')", "Bash(git stash pop)",
"Bash(git stash push -u -m 'git-fresh-*')",
"Bash(git merge --ff-only origin/main)", "Bash(git merge --ff-only origin/master)",
"Bash(git switch main)", "Bash(git switch master)"
```
- enumerated rather than one broad git allow, since a plain push to a feature branch is not denied
- an incomplete allowlist costs a prompt; an incomplete denylist costs a silent hole
- `git branch`, `git tag`, `git remote` and `git reflog` are bare-only, so the mutating forms miss
- `git merge-base` and `git merge-tree` survive because the merge deny requires a bare form or a space
- `git fetch` is the one non-read here: it moves remote-tracking refs, which the atomic loop needs
- `AGENTS/shared/handover.sh` is written against this list, so a sidecar cannot drift out of it
- the second block is the mutating exception, and every rule in it is a literal or a message glob
- literals rather than `git switch *`, so the floor refuses a create or a discard without the hook
- `git stash push` is allowed only under the two messages the triggers write, never a bare form
- `--ff-only` is spelled into the rule, so a merge that could lose work never matches it
- these mirror `settings.project.json` exactly; a deny here would outrank the allow there

## permissions.ask

### escape — the visible hatch
```json
"Bash(dangerouslyDisableSandbox:true)",
```
- every unsandboxed retry stays visible, which is what makes `allowUnsandboxedCommands` safe

### policy — hand-edited only
```json
"Write(.claude/**)", "Edit(.claude/**)",

"Edit(AGENTS/**)", "Write(AGENTS/**)",
```
- an agent that can rewrite these can grant itself anything
- one rule per verb, since everything under `AGENTS/` either executes or instructs
- it replaced three narrower globs on 2026-08-04, which had left 19 markdown files ungated:
  the nine `@git*` triggers and the ten templates
- a trigger doc is policy too: `git-fresh.md` carries the line telling an agent never to reset,
  and `templates/git.md` is where the read-only contract for every sidecar is written
- rewriting one never beats the deny floor, but it does mislead the next session
- `Bash(AGENTS/**/*.sh*)` stays on allow, so gating the edit never gates the run
- the settings and the code enforcing them together; gating one leaves the rules protected and the enforcement editable
- deny until 2026-08-04, and deny broke git rather than the agent: the projected deny refused the unlink a checkout needs
- ask is the honest trade: the threat is an agent rewriting policy on its own initiative, and a prompt stops exactly that
- `pretooluse.sh` refuses bash writes into all three, so the prompt is the second layer rather than the only one
- it had covered `.claude/` alone until 2026-08-04, leaving the AGENTS paths on the prompt by itself

### runners — one-shot remote execution
```json
"Bash(npx*)",
"Bash(bunx*)", "Bash(uvx*)",
"Bash(pnpm dlx*)", "Bash(pnpm -* dlx*)",
"Bash(yarn dlx*)", "Bash(yarn -* dlx*)",
"Bash(bun x*)", "Bash(bun -* x*)",
"Bash(pipx run*)", "Bash(pipx -* run*)",
"Bash(uv tool run*)", "Bash(uv -* tool run*)",
"Bash(deno run*)", "Bash(deno -* run*)",
"Bash(go run*)", "Bash(go -* run*)",
```
- each fetches code from a registry and executes it in one command
- the sandbox contains the filesystem, never the credential: a masked token is unreadable and still spendable
- cwd stays writable, so a package can edit the repo and wait for you to commit it
- ask beats allow from any scope, overriding every project's npx allow
- the interposed twin is `-*`, never a bare `*`, so the wildcard covers flags rather than subcommands
- install-time scripts are deliberately absent: a prompt per install trains click-through, and `--ignore-scripts` is the real control

### find — arbitrary execution, ordinary work
```json
"Bash(find * -exec *)"
```
- `-exec` runs anything, but wrapped around everyday search work, so a prompt fits

## permissions.deny
grouped most-destructive-first; any scope may add a deny, none may remove another's

### policy — the scope git never touches
```json
"Write(~/.claude/**)", "Edit(~/.claude/**)",
```
- stays deny while the tracked siblings moved to ask: nothing here is under version control
- this is the file carrying the credential config, so it keeps the stricter rule

### system — root, disk, recursive delete
```json
"Bash(sudo *)",
"Bash(mkfs*)", "Bash(dd *)",
"Bash(rm -rf *)", "Bash(rm -fr *)", "Bash(rm -R *)", "Bash(rm -r *)",
"Bash(chmod -R *)", "Bash(chown -R *)",
"Bash(shred *)", "Bash(find * -delete*)",
```
- irreversible at machine scale, and none of it has a legitimate agent use

### execution — code from a string
```json
"Bash(eval *)",
"Bash(node -e *)", "Bash(node --eval *)",
"Bash(python -c *)", "Bash(python3 -c *)",
"Bash(perl -e *)", "Bash(ruby -e *)",
"Bash(curl * | bash)", "Bash(curl * | sh)", "Bash(curl * | python*)",
"Bash(wget * | bash)", "Bash(wget * | sh)", "Bash(wget * | python*)",
"Bash(*fs.rm*)", "Bash(*fs.unlink*)", "Bash(*fs.rmdir*)", "Bash(*rimraf*)",
```
- a string is not reviewable before it runs, which is the whole objection

### remote — repo, identity and secrets on the server
```json
"Bash(gh repo delete*)", "Bash(gh repo archive*)", "Bash(gh release delete*)",
"Bash(gh auth *)", "Bash(gh ssh-key *)", "Bash(gh gpg-key *)",
"Bash(gh secret *)", "Bash(gh variable *)",
```
- outward-facing and hard to undo
- kept even though gh cannot verify tls sandboxed, since the retry hatch and a plain terminal both reach it

### data — stores that do not come back
```json
"Bash(dropdb *)", "Bash(db:drop*)", "Bash(prisma migrate reset*)",
```

### git — everything that mutates, executes, or egresses
> `@git*` sidecars measure and hand these back; none of them runs one
```json
"Bash(git -c *)", "Bash(git -C *)", "Bash(git --exec-path*)",
"Bash(git --git-dir*)", "Bash(git --work-tree*)", "Bash(git --namespace*)",
"Bash(git * --output*)",

"Bash(git shell*)", "Bash(git credential*)", "Bash(git config*)",
"Bash(git daemon*)", "Bash(git instaweb*)", "Bash(git http-backend*)",
"Bash(git upload-pack*)", "Bash(git receive-pack*)", "Bash(git cvsserver*)",
"Bash(git remote-ext*)", "Bash(git remote-fd*)", "Bash(git web--browse*)",
"Bash(git imap-send*)", "Bash(git send-email*)", "Bash(git request-pull*)",
"Bash(git difftool*)", "Bash(git mergetool*)",

"Bash(git push*)",

"Bash(git filter-branch*)", "Bash(git filter-repo*)",
"Bash(git fast-import*)", "Bash(git fast-export*)",
"Bash(git rebase*)", "Bash(git cherry-pick*)", "Bash(git revert*)", "Bash(git replace*)",
"Bash(git am*)", "Bash(git apply*)", "Bash(git quiltimport*)",
"Bash(git commit)", "Bash(git commit *)", "Bash(git commit-tree*)",
"Bash(git merge)", "Bash(git merge-file*)", "Bash(git pull*)",

"Bash(git reset*)", "Bash(git restore*)", "Bash(git checkout*)",
"Bash(git switch)", "Bash(git switch -c*)", "Bash(git switch -C*)", "Bash(git switch -d*)",
"Bash(git switch -f*)", "Bash(git switch -t*)", "Bash(git switch --create*)",
"Bash(git switch --force-create*)", "Bash(git switch --force*)", "Bash(git switch --detach*)",
"Bash(git switch --discard-changes*)", "Bash(git switch --orphan*)", "Bash(git switch --track*)",
"Bash(git switch --guess*)", "Bash(git switch --ignore-other-worktrees*)",
"Bash(git clean*)", "Bash(git rm*)", "Bash(git mv*)", "Bash(git add*)",
"Bash(git bisect*)", "Bash(git sparse-checkout*)", "Bash(git worktree*)",
"Bash(git submodule*)", "Bash(git rerere*)",

"Bash(git stash)", "Bash(git stash save*)",
"Bash(git stash apply*)", "Bash(git stash drop*)",
"Bash(git stash clear*)", "Bash(git stash branch*)", "Bash(git stash create*)",
"Bash(git stash store*)",

"Bash(git branch -d*)", "Bash(git branch -D*)", "Bash(git branch -f*)",
"Bash(git branch -m*)", "Bash(git branch -M*)", "Bash(git branch -c*)", "Bash(git branch -C*)",
"Bash(git branch --delete*)", "Bash(git branch --force*)", "Bash(git branch --move*)",
"Bash(git branch --copy*)", "Bash(git branch --edit-description*)", "Bash(git branch --set-upstream*)",
"Bash(git tag -d*)", "Bash(git tag -f*)", "Bash(git tag -a*)", "Bash(git tag -s*)",
"Bash(git tag --delete*)", "Bash(git tag --force*)", "Bash(git tag --sign*)",
"Bash(git update-ref*)", "Bash(git symbolic-ref*)", "Bash(git notes*)",
"Bash(git remote add*)", "Bash(git remote remove*)", "Bash(git remote rm*)",
"Bash(git remote set-url*)", "Bash(git remote set-head*)", "Bash(git remote set-branches*)",
"Bash(git remote rename*)", "Bash(git remote prune*)", "Bash(git remote update*)",

"Bash(git update-index*)", "Bash(git read-tree*)", "Bash(git write-tree*)",
"Bash(git hash-object*)", "Bash(git checkout-index*)", "Bash(git mktree*)", "Bash(git mktag*)",
"Bash(git pack-objects*)", "Bash(git unpack-objects*)", "Bash(git index-pack*)",
"Bash(git pack-refs*)", "Bash(git prune-packed*)", "Bash(git update-server-info*)",

"Bash(git gc*)", "Bash(git prune*)", "Bash(git repack*)", "Bash(git maintenance*)",
"Bash(git fsck*)", "Bash(git reflog expire*)", "Bash(git reflog delete*)",

"Bash(git clone*)", "Bash(git init*)", "Bash(git bundle*)", "Bash(git archive*)",
"Bash(git format-patch*)", "Bash(git bugreport*)", "Bash(git diagnose*)",
"Bash(git svn*)", "Bash(git p4*)", "Bash(git cvsimport*)", "Bash(git cvsexportcommit*)",
```
- the global flags lead, since they sit *before* the subcommand and every rule below is prefix-anchored
- `git -c core.pager='sh -c ...' log` is arbitrary execution wearing a read-only subcommand
- denying them is what lets the rest stay single-form instead of needing `git * <verb>*` twins
- `git credential fill` prints the credential, so it is a read command that reads the wrong thing
- `git config*` goes broad and denies its read forms too, since `core.pager`, `gpg.program`,
  `diff.external`, `filter.*.clean` and `init.templateDir` all execute
- `git remote-ext` runs commands as a transport, and `git shell -c` is a shell
- `git * --output*` is one rule for a write hiding inside `diff`, `log` and their siblings
- `git merge` and `git commit` are split into bare-plus-space forms, so `merge-base`,
  `merge-tree` and `commit-tree` stay readable on the allow side
- `git branch -c*` does not eat `--contains` and `-m*` does not eat `--merged`, since the
  match fails at the second character
- `git push*` collapses the twelve old push rules, now that nothing pushes from an agent
- `@git-fresh` hands these back rather than running them, which is the pattern to copy

### credentials — every verb, on every store
```json
"Read(//**/.env*)", "Write(//**/.env*)", "Edit(//**/.env*)",
"Read(~/**/*.pem)", "Write(~/**/*.pem)", "Edit(~/**/*.pem)",
"Read(~/**/*.crt)", "Write(~/**/*.crt)", "Edit(~/**/*.crt)",
"Read(//**/*.key)", "Write(//**/*.key)", "Edit(//**/*.key)",
"Read(//**/*.p12)", "Write(//**/*.p12)", "Edit(//**/*.p12)",
"Read(~/.ssh/**)", "Write(~/.ssh/**)", "Edit(~/.ssh/**)",
"Read(~/.aws/**)", "Write(~/.aws/**)", "Edit(~/.aws/**)",
"Read(~/.config/gcloud/**)", "Write(~/.config/gcloud/**)", "Edit(~/.config/gcloud/**)",
"Read(~/.kube/**)", "Write(~/.kube/**)", "Edit(~/.kube/**)",
"Read(~/.gnupg/**)", "Write(~/.gnupg/**)", "Edit(~/.gnupg/**)",
"Read(~/.netrc)", "Write(~/.netrc)", "Edit(~/.netrc)",
"Read(~/.npmrc)", "Write(~/.npmrc)", "Edit(~/.npmrc)",
"Read(~/.bash_history)", "Write(~/.bash_history)", "Edit(~/.bash_history)",
"Read(~/.zsh_history)", "Write(~/.zsh_history)", "Edit(~/.zsh_history)",
"Read(~/Library/Keychains/**)", "Write(~/Library/Keychains/**)", "Edit(~/Library/Keychains/**)",
```
- **a read deny is not a deny**: these carried `Read` alone until 2026-08-03, safe only while no allow reached them
- the broad `Write` and `Edit` allow would have made `~/.ssh/authorized_keys` writable in silence
- one path per row, three verbs on it, so a missing verb is visible without running the audit

### persistence — code that outlives the session
```json
"Read(~/.zshrc)", "Write(~/.zshrc)", "Edit(~/.zshrc)",
"Read(~/.zshenv)", "Write(~/.zshenv)", "Edit(~/.zshenv)",
"Read(~/.zprofile)", "Write(~/.zprofile)", "Edit(~/.zprofile)",
"Read(~/.bashrc)", "Write(~/.bashrc)", "Edit(~/.bashrc)",
"Read(~/.bash_profile)", "Write(~/.bash_profile)", "Edit(~/.bash_profile)",
"Read(~/.profile)", "Write(~/.profile)", "Edit(~/.profile)",

"Bash(launchctl *)", "Bash(osascript *)", "Bash(defaults write *)",
"Bash(git config *core.hooksPath*)", "Bash(git config *alias.*)",
```
- anything installed here runs in every future shell, escaping every layer above it
- `core.hooksPath` turns every later git command into arbitrary execution
- the rc files carry `Read` too, since they name where the token store lives
- `crontab` needs no rule; seatbelt refuses it outright, measured 2026-08-03

### keychain — the daemon the file rules cannot see
```json
"Bash(security *)",
```
- the cli talks to keychaind rather than the files denyRead covers
- same class of gap as gh and cgo: a path deny never sees a daemon channel

### exfiltration — moving bytes off the machine
```json
"Bash(nc *)", "Bash(ncat *)", "Bash(socat *)", "Bash(scp *)",
```

### publish — outward-facing and irreversible
```json
"Bash(npm publish*)", "Bash(npm -* publish*)",
"Bash(pnpm publish*)", "Bash(pnpm -* publish*)",
"Bash(yarn publish*)", "Bash(yarn -* publish*)",
"Bash(docker push*)", "Bash(docker -* push*)",
```
- unpublishing is limited or impossible, so there is nothing for a prompt to weigh

### infrastructure — state that does not come back
```json
"Bash(aws s3 rm *)", "Bash(aws -* s3 rm *)",
"Bash(kubectl delete *)", "Bash(kubectl -* delete *)",
"Bash(terraform destroy*)", "Bash(terraform -* destroy*)"
```
- none of these run on this machine today; the rules are insurance that travels

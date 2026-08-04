# settings.user.json
> copy to `~/.claude/settings.json` — mechanics live in [README.md](../../README.md), this file
> covers only why these values, in this scope

the working floor for every repo on this disk. a fix here needs an editor rather than sudo, which
is why unproven values live here until they have run clean long enough to promote to managed.

## sandbox

`"enabled": true`
- restated so a directory that is not a repo stays sandboxed even with no managed file installed

`"failIfUnavailable": true`
- refuses to start rather than running unsandboxed, and sits here so a lockout stays editable

`"allowUnsandboxedCommands": true`
- the retry hatch stays open for attended work; the ask below is what makes each escape visible
- set it false in project for any repo running unattended

`"enableWeakerNetworkIsolation": true`
- re-permits the trustd lookup go needs for tls, which is what gh fails without
- verify egress still refuses an unlisted host after enabling it

### filesystem
`allowWrite` — `~/.npm` `~/.cache` `~/Library/pnpm` `~/Library/Caches/pnpm`
- this machine's package-manager scribble, and the one block that is pure machine detail
- it misses the cache Zed exports as npm_config_cache

`denyRead` — `/Volumes` `~/Library/Keychains`
- the odd extras the permission layer does not already cover

`denyWrite` — empty
- a write outside `allowWrite` already fails, so listing paths here would be theatre

### network
`strictAllowlist` `tlsTerminate`
- strict denies unlisted hosts; without it the list only suppresses prompts
- tls termination is what lets the proxy swap a masked credential in, and mask fails closed without it

`allowedDomains` — `code.claude.com` `docs.claude.com` `github.com` `api.github.com` `registry.npmjs.org`
- named hosts only, since a github wildcard reaches gist
- every repo on this disk inherits these, read or unread
- `github.com` and `api.github.com`: git over https, and the api every sidecar reaches by curl
- `registry.npmjs.org`: npm and pnpm installs, matching the caches in `allowWrite`
- `code.claude.com` and `docs.claude.com`: WebFetch allows that also seed the bash allowlist

### credentials
> hides a secret from sandboxed bash only; the Read, Edit and Write tools need a permission rule

- `files` refuses reads on a path, and `deny` is the only mode it accepts
- `envVars` unsets a name before each sandboxed command, and survives `filesystem.disabled`
- `mask` substitutes a sentinel rather than unsetting, so the tool still authenticates
- an entry with an empty path or name is stripped with a warning at startup

`files` — the token stores, all `deny`
- `~/.operator/.env` is listed here and caught by the `.env*` rule, so either regression still holds
- that directory must be chmod 700 on creation, since umask gives a new home dir 755

`envVars` — provider keys, all `deny`
- `IGCLI_SERP_KEY` came from probing the environment rather than from any list
- `NPM_TOKEN` is publish-only, so installs are unaffected
- `GITHUB_TOKEN` stays denied, holding an unrelated gitascms credential

`GH_TOKEN` — `mask`, injected to `api.github.com` and `github.com`
- the sandbox sees a sentinel while the proxy substitutes the real value at the edge
- a masked name must never also be denied, since deny wins in every scope
- every `injectHosts` entry must also sit in `allowedDomains`, or the mask fails closed
- honored from user, managed and cli only, so the same block in project or local is inert
- mask stops a token persisting, never stops it being spent, so the pat's scope is the real limit

## permissions.allow

`Read` `Write` `Edit`
- broad by design: the deny floor carries the weight, and an enumerated allowlist goes stale
  every time a file is added, which it did twice before this changed

`WebSearch`
- no egress of repo content, so nothing to gate

`Bash(AGENTS/**/*.sh*)`
- the sidecars, in regular-permissions mode; the `*` tail is what matches arguments, and a bare
  `.sh` silently matched only a bare invocation

## permissions.ask

`Bash(dangerouslyDisableSandbox:true)`
- every unsandboxed retry stays visible, which is what makes `allowUnsandboxedCommands` safe

`Edit(AGENTS/**/*.sh)` `Write(AGENTS/**/*.sh)`
- editing the automation is a decision rather than a default; a no-match prompt already gated
  these, but that gate is invisible and one broadened allow erases it

`Bash(npx*)` `Bash(bunx*)` `Bash(uvx*)` `Bash(pnpm dlx*)` `Bash(pnpm -* dlx*)` `Bash(yarn dlx*)`
`Bash(yarn -* dlx*)` `Bash(bun x*)` `Bash(bun -* x*)` `Bash(pipx run*)` `Bash(pipx -* run*)`
`Bash(uv tool run*)` `Bash(uv -* tool run*)` `Bash(deno run*)` `Bash(deno -* run*)`
`Bash(go run*)` `Bash(go -* run*)`
- one-shot remote runners: each fetches code from a registry and executes it in one command
- the sandbox contains the filesystem, never the credential — a masked token is unreadable inside
  the box and still spendable against `api.github.com`, bounded only by the pat's scope
- cwd stays writable, so a package can edit the repo and wait for you to commit it
- ask beats allow from any scope, so these override every project's npx allow
- the interposed twin is `-*`, never a bare `*`: `go * run*` also matches `go build ./cmd/runner`
- install-time scripts are deliberately absent: same risk, but a prompt per install trains you to
  click through, and `--ignore-scripts` is the real control

`Bash(find * -exec *)`
- arbitrary execution, but `find . -name '*.ts' -exec grep -l foo {} +` is ordinary work

`Write(.claude/**)` `Edit(.claude/**)`
`Write(AGENTS/hooks/**)` `Edit(AGENTS/hooks/**)` `Write(AGENTS/settings/**)` `Edit(AGENTS/settings/**)`
- hand-edited only: an agent that can rewrite these can grant itself anything
- the settings and the code that enforces them, since denying one without the other leaves the
  rules protected and the enforcement editable
- these were deny until 2026-08-04, and deny broke git rather than the agent: a deny reaches the
  macos sandbox, which refuses the unlink a branch switch needs, stranding files mid-checkout
- all three are tracked, so git has to rewrite them on any checkout that changes them
- ask is the honest trade here, since the threat is an agent rewriting policy on its own initiative
  and a prompt stops exactly that, while the sandbox block stopped ordinary version control
- `pretooluse.sh` refuses any command naming these paths regardless, so the prompt is the second
  layer rather than the only one

## permissions.deny

### policy — the scope git never touches
`Write(~/.claude/**)` `Edit(~/.claude/**)`
- stays deny while its tracked siblings moved to ask, since nothing here is under version control
- no git operation reaches the user scope, so the hard block costs nothing and the relaxation
  would buy nothing; this is the file carrying the credential config, so it keeps the stricter rule

### system — root, disk, recursive delete
`Bash(sudo *)` `Bash(mkfs*)` `Bash(dd *)`
`Bash(rm -rf *)` `Bash(rm -fr *)` `Bash(rm -R *)` `Bash(rm -r *)`
`Bash(chmod -R *)` `Bash(chown -R *)` `Bash(shred *)` `Bash(find * -delete*)`
- irreversible at machine scale, and none of it has a legitimate agent use

### execution — code from a string
`Bash(eval *)` `Bash(node -e *)` `Bash(node --eval *)` `Bash(python -c *)` `Bash(python3 -c *)`
`Bash(perl -e *)` `Bash(ruby -e *)`
`Bash(curl * | bash)` `Bash(curl * | sh)` `Bash(curl * | python*)`
`Bash(wget * | bash)` `Bash(wget * | sh)` `Bash(wget * | python*)`
`Bash(*fs.rm*)` `Bash(*fs.unlink*)` `Bash(*fs.rmdir*)` `Bash(*rimraf*)`
- a string is not reviewable before it runs, which is the whole objection

### remote — repo, identity, and history on the server
`Bash(gh repo delete*)` `Bash(gh repo archive*)` `Bash(gh release delete*)`
`Bash(gh auth *)` `Bash(gh ssh-key *)` `Bash(gh gpg-key *)` `Bash(gh secret *)` `Bash(gh variable *)`
`Bash(git push --mirror*)` `Bash(git push * --mirror*)` `Bash(git push --prune*)`
`Bash(git push * --prune*)` `Bash(git push --delete*)` `Bash(git push * --delete*)`
`Bash(git push --force*)` `Bash(git push -f*)` `Bash(git push * --force*)` `Bash(git push * -f*)`
`Bash(git push origin main*)` `Bash(git push origin master*)`
- outward-facing and hard to undo; the `* --force*` twins exist because deny is prefix-anchored
  and a trailing flag walks straight past a rule without them

### data — stores that do not come back
`Bash(dropdb *)` `Bash(db:drop*)` `Bash(prisma migrate reset*)`

### history — the local record
`Bash(git filter-branch*)` `Bash(git reflog expire*)` `Bash(git update-ref -d*)` `Bash(git gc --prune*)`
`Bash(git branch -D*)` `Bash(git branch * -D*)` `Bash(git branch -f*)` `Bash(git branch * -f*)`
`Bash(git branch --force*)` `Bash(git branch --delete --force*)` `Bash(git reset --hard*)`
`Bash(git checkout -f*)` `Bash(git checkout --force*)`
`Bash(git clean -f*)` `Bash(git clean -d*)` `Bash(git clean -x*)` `Bash(git clean * -f*)`
`Bash(git stash clear*)` `Bash(git stash drop*)`
- `@gitfresh` hands these back rather than running them, which is the pattern to copy

### credentials — every verb, on every store
`Read(//**/.env*)` `Write(//**/.env*)` `Edit(//**/.env*)`
`Read(~/**/*.pem)` `Write(~/**/*.pem)` `Edit(~/**/*.pem)`
`Read(~/**/*.crt)` `Write(~/**/*.crt)` `Edit(~/**/*.crt)`
`Read(//**/*.key)` `Write(//**/*.key)` `Edit(//**/*.key)`
`Read(//**/*.p12)` `Write(//**/*.p12)` `Edit(//**/*.p12)`
`Read(~/.ssh/**)` `Write(~/.ssh/**)` `Edit(~/.ssh/**)`
`Read(~/.aws/**)` `Write(~/.aws/**)` `Edit(~/.aws/**)`
`Read(~/.config/gcloud/**)` `Write(~/.config/gcloud/**)` `Edit(~/.config/gcloud/**)`
`Read(~/.kube/**)` `Write(~/.kube/**)` `Edit(~/.kube/**)`
`Read(~/.gnupg/**)` `Write(~/.gnupg/**)` `Edit(~/.gnupg/**)`
`Read(~/.netrc)` `Write(~/.netrc)` `Edit(~/.netrc)`
`Read(~/.npmrc)` `Write(~/.npmrc)` `Edit(~/.npmrc)`
`Read(~/.bash_history)` `Write(~/.bash_history)` `Edit(~/.bash_history)`
`Read(~/.zsh_history)` `Write(~/.zsh_history)` `Edit(~/.zsh_history)`
`Read(~/Library/Keychains/**)` `Write(~/Library/Keychains/**)` `Edit(~/Library/Keychains/**)`
- **a read deny is not a deny.** these carried `Read` alone until 2026-08-03, which was safe only
  while no allow reached them; the broad `Write`/`Edit` allow above would have made
  `~/.ssh/authorized_keys` writable in silence
- one path per row, three verbs on it, so a missing verb is visible without running the audit

### persistence — code that outlives the session
`Bash(launchctl *)` `Bash(osascript *)` `Bash(defaults write *)`
`Bash(git config *core.hooksPath*)` `Bash(git config *alias.*)`
`Read(~/.zshrc)` `Write(~/.zshrc)` `Edit(~/.zshrc)`
`Read(~/.zshenv)` `Write(~/.zshenv)` `Edit(~/.zshenv)`
`Read(~/.zprofile)` `Write(~/.zprofile)` `Edit(~/.zprofile)`
`Read(~/.bashrc)` `Write(~/.bashrc)` `Edit(~/.bashrc)`
`Read(~/.bash_profile)` `Write(~/.bash_profile)` `Edit(~/.bash_profile)`
`Read(~/.profile)` `Write(~/.profile)` `Edit(~/.profile)`
- anything installed here runs in every future shell, escaping every layer above it
- `core.hooksPath` is the sneakiest: it turns every later git command into arbitrary execution
- the rc files carry `Read` too, since they name where the token store lives
- `crontab` needs no rule; seatbelt refuses it outright, measured 2026-08-03

### keychain — the daemon the file rules cannot see
`Bash(security *)`
- `security list-keychains` answers normally under the sandbox, because the cli talks to keychaind
  rather than to the files `denyRead ~/Library/Keychains` covers
- same class of gap as gh and cgo: a path deny never sees a daemon channel

### exfiltration — moving bytes off the machine
`Bash(nc *)` `Bash(ncat *)` `Bash(socat *)` `Bash(scp *)`

### publish — outward-facing and irreversible
`Bash(npm publish*)` `Bash(npm -* publish*)` `Bash(pnpm publish*)` `Bash(pnpm -* publish*)`
`Bash(yarn publish*)` `Bash(yarn -* publish*)` `Bash(docker push*)` `Bash(docker -* push*)`
- unpublishing is limited or impossible, so there is nothing for a prompt to weigh

### infrastructure — state that does not come back
`Bash(aws s3 rm *)` `Bash(aws -* s3 rm *)` `Bash(kubectl delete *)` `Bash(kubectl -* delete *)`
`Bash(terraform destroy*)` `Bash(terraform -* destroy*)`
- none of these run on this machine today, so the rules are insurance that travels

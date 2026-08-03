# AGENT PLAN: Operation Claude Sandbox
harness an agent safely on this machine by containing it instead of trusting it

## Context
- agentic coding needs autonomy, and bypassing permissions bought it with every guardrail (see #1)
- full exposure felt wrong and a dedicated machine for basic features is overkill
- the fix is containment: a sandbox boundary plus a deny floor instead of a longer allow list
- one settings toggle turned out to be five scopes and two engines with opposite tiebreaks
- working guardrails: suggestions by default and no files touched outside declared targets

## Goal
agentic work runs promptless inside a contained boundary that is documented, tested, and portable
```
/Library/.../managed-settings.json  the ceiling: booleans, credential locks, the deny floor
~/.claude/settings.json             machine detail: cache paths, the developer read, websearch
.claude/settings.json               the travelling copy: floor, npx ask, gh exclusion, egress
.claude/settings.local.json         hooks, enabled, and accumulated grants
AGENTS/settings/*.jsonc             the four templates the live files are copied from
AGENTS/security/permissions.sh      replays corpus strings through the live hook
AGENTS/security/scopes.sh           maps a workflow against a stack of settings files
AGENTS/security/corpus.tsv          command strings with expected verdicts, sidecars included
README.md                           precedence, diagnostics, guidance, and cited sources
```

## Solution
- contain with the sandbox rather than enumerate; deny and ask are the only live levers (see #2)
- duplicate the floor and the npx ask into project, the one scope that travels (see #3)
- keep allows at the narrowest scope and denies at the widest (see #4)
- map workflows statically before installing anything (see #5, #10)
- treat the script file as the unit of trust, so the tester reports per script (see #6)

## Risks
- `lockout` a broken managed file stops claude from starting at all (see #7)
- `silent egress` a returning bare WebFetch reopens every domain for sandboxed bash (see #8)
- `open door` one excluded command in a string unsandboxes the whole string (see #26)
- `hidden escape` an open retry hatch turns a sandbox gap into a silent success (see #20)
- `own goal` a deny written for secrets can match a system file every tool needs (see #19)
- `misfire` no sidecar parses arguments, so a stray `--test` delivers for real (see #11)
- `proxy stall` gh survives seatbelt but is untested against a live domain allowlist (see #9)

## Checklist

### 1. Document the precedence system
- [x] fetch the four doc pages behind the sources section
- [x] correct the readme priority block against citations
- [x] restructure into tiers from hook to additive with numbered notes
- [x] group the notes under linked source headings
- [x] verify note references resolve one to one

### 2. Draft diagnostics and scope guidance
- [x] write the symptom to layer to fix table
- [x] add the resolved-config and corpus instrument lines
- [x] land will's stop-at-first-yes scope questions
- [x] fold grants into precedence as cited notes

### 3. Teach the plan template permissions
- [x] add layer and scope columns to the permissions table
- [x] extend plans.sh checks to match the new columns
- [x] prove bad layer and scope rows fail with a negative test
- [x] migrate the prior plan to the new shape

### 4. Unbreak the sidecars under the sandbox
- [x] probe why mktemp dies sandboxed and ignores TMPDIR
- [x] convert all 12 sidecars to repo-local tmp scratch
- [x] gitignore tmp and keep the cleanup traps correct
- [x] add --keep and preserve scratch on failing runs
- [x] rerun the validators sandboxed with no bypass

### 5. Configure the settings templates
- [x] rebuild managed with envVars denies and the npx ask
- [x] shrink user to cache paths and reads only
- [x] copy the deny floor and npx ask into project verbatim
- [x] exclude gh and narrow WebFetch in project
- [x] name github.com and the npm registry as sandboxed egress
- [x] sync all four wayfinders and verify json and widths
- [x] add the policy block to managed and project, since edit and write skip the sandbox (see #13)
- [x] add the generated block to project alone, keeping repo-shaped paths out of managed
- [x] order every deny block to match the readme, policy first

### 6. Build the scope tester
- [x] write scopes.sh to parse a stack of settings files
- [x] replay each script's own invocation through the live hook
- [x] extract every command a sidecar invokes internally
- [x] resolve which internals touch paths, domains, or denied reads
- [x] decide each internal against the merged sandbox boundary
- [x] report pass, ask, and fail per layer with a fix line
- [x] resolve a bare repo name to its settings stack, as `--repo` on the tester (see #12)
- [ ] document the tester and its flags in each trigger's FLAGS block (see #15)
- [ ] guard the four destructive sidecars so a stray `--test` cannot execute (see #11)
- [x] decide the gh-in-sidecar remediation pattern
- [ ] grow corpus.tsv with argument-bearing sidecar calls and cat .env
- [x] validate the tester against gitdeliver, then against all 28 scripts (see #16)
- [ ] rerun the tester with the four templates staged as the stack, before installing them

### 7. Install the user-first stack
- [x] narrow the pem deny in the live project file, which blocks the ca bundle (see #19)
- [x] copy the user template to ~/.claude/settings.json, floor and credentials included (see #21)
- [x] name github.com and the npm registry in the live project file (see #17)
- [x] carry the npx allow into the live project file, replacing the ask it never had (see #14)
- [x] drop the gh exclusion rather than restore it, since it unsandboxes whole strings (see #26)
- [x] drop both ~/.config/gh denies so gh can start sandboxed (see #23, #26)
- [x] set enableWeakerNetworkIsolation, which fixes go tls verification (see #27)
- [x] add strictAllowlist, without which the allowlist only suppresses prompts (see #28)
- [x] keep managed to the four keys only managed can set (see #21)
- [x] run the six probes and diff each result against today's baseline (see #22)
- [x] prefix the env denies so they reach beyond the current project (see #31)
- [x] create MBP2021_OPERATOR and source it from ~/.operator/.env, chmod 700 (see #32)
- [x] add a readme machine keys section, placed beside credentials rather than in the appendix
- [ ] add the zed npm cache to allowWrite, or unset npm_config_cache (see #24)
- [ ] copy the user template live, then restart zed so the shell env carries GH_TOKEN (see #29)
- [x] verify the token file is unreadable to sandboxed bash (see #29, #34)
- [x] verify gh against the masked sentinel; it cannot, so curl replaces it (see #18, #33)
- [x] expect git push to need its own credential path, since git ignores GH_TOKEN (see #30)
- [x] rewrite the sidecars' gh api calls against curl, the only client mask can serve (see #33)
- [ ] regrant the pat contents read and write plus pull requests write, then rerun the release
      and update-branch writes, since every write path 403s today (see #37)
- [x] decide whether delivery stays attended: it does, mask stays on, push uses the hatch (see #35)
- [ ] revisit only if gh ships without cgo, or the proxy substitutes inside base64 (see #33)
- [ ] confirm the resolved merge in the /sandbox config tab
- [ ] run gitdeliver end to end, then score the run against the predictions (see #25)
- [ ] run the tester against ownershive's project and local files (see #12)
- [ ] rerun permissions.sh and triage what changed
- [x] rebuild the readme deny section as a managed half and a project half
- [x] document failIfUnavailable, sandbox credentials, and the npm symptom in the readme
- [x] fold the readme findings back into these notes, leaving conclusions in the readme sections
- [ ] add a readme allow section once the live stack shows what actually merged

### 8. Serve the onboarding period, then promote
- [ ] treat every dangerouslyDisableSandbox prompt as one missing flag, and fix that flag (see #20)
- [ ] set allowUnsandboxedCommands false in the project file of any repo running unattended
- [ ] hold until a full week passes with no escape prompt and no hand-edited setting
- [ ] promote the deny floor and the credentials block from user to managed, one block at a time
- [ ] keep allowUnsandboxedCommands and failIfUnavailable out of managed, both one-way (see #21)
- [ ] rerun the six probes after each promotion, since every managed key changes the merge
- [ ] rerun the verification snapshot alongside them, and record what moved (see #36)

### Deferred Work
- [ ] fix wayfinders.sh crashing when a path holds no eligible files
- [ ] decide whether the node deletes belong in system rather than execution
- [ ] build the tier 3 dynamic harness on sandbox-runtime with a scratch remote
- [ ] add an add-to-ask action to the plans.sh vocabulary
- [ ] preflight gh and jq, the two binaries macos does not ship
- [ ] carve the memory directory out of the deny list or accept no cross-session memory
- [ ] create AGENTS.md or repoint its 51 references
- [ ] document the ~/.operator install contract, since 700 is what makes the store private
- [ ] audit every unprefixed permission rule, since the env one hid a machine-wide hole (see #31)

## Readiness

### Blockers
none; nothing in another open plan gates starting this one

### Agents
how each stage's checklist items are split by who can run them:

| stage | agentic | human-only | gated | note # |
|---|---|---|---|---|
| 1. document precedence | 5 | — | — | see #1 |
| 2. diagnostics and guidance | 3 | 1 | — | see #4 |
| 3. plan template permissions | 4 | — | — | see #2 |
| 4. sidecars under the sandbox | 5 | — | — | see #6 |
| 5. settings templates | 9 | — | — | see #3 |
| 6. scope tester | 3 | 1 | 9 | see #5 |
| 7. install the user-first stack | 12 | 16 | 1 | see #7 |
| 8. onboarding and promotion | 2 | 5 | — | see #21 |

### Permissions
suggested rules to set in order for agents to work reliably:

| rule | layer | scope | suggestion |
|---|---|---|---|
| 1. `Bash(AGENTS/security/*.sh*)` | permissions | project | add to allow |
| 2. `github.com` | sandbox domain | project | add to allowedDomains |
| 3. `registry.npmjs.org` | sandbox domain | project | add to allowedDomains |
| 4. `~/Library/Caches/pnpm` | sandbox filesystem | user | add to allowWrite |
| 5. `Read(//**/*.pem)` | permissions | project | narrow deny |

#### Explanations
1. quoted from the project template; the live file lacks it, so tester runs prompt until stage 7
2. quoted from the project template; sidecar git fetch and push resolve there
3. quoted from the project template; future package installs resolve there
4. quoted from the user template; pnpm writes its cache outside cwd on every run
5. quoted from the live project file; it matches the public ca bundle, so tls fails (see #19)

## Notes
1. the exercise began as bypass-all-permissions, which traded every guardrail for autonomy
2. sandboxed commands never consult the allow list, so deny and ask are the only live levers
3. a bare clone sets enabled true and auto-allows, so the npx ask must travel inside project
4. denies only narrow and allows carry blast radius, so denies go wide and allows go narrow
5. gh runs as a sandboxed child in four git sidecars, where the top-level exclusion never applies
6. permission rules see one string per script; the tester counted 5,674 internals crossing no gate
7. only a human can install or repair managed, since the floor itself denies agents sudo
8. a bare WebFetch equals domain star and seeds the bash allowlist with every host
9. measured sandboxed: gh reached the api and git ls-remote authenticated over https, so the
   seatbelt tls warning is moot here; the proxy was not enforcing an allowlist during that test
10. tiers: static scan now, corpus replay alongside, sandbox-runtime dynamic only if doubt remains
11. no sidecar parses arguments, so the flag lives in the trigger doc with a guard in the script
12. a flag per repo does not scale, so `--test [repo]` takes a name resolved under ~/Developer
13. edit and write never enter the sandbox, so its settings.json protection covers bash alone
14. the live project file carries no ask block, so npx has been auto-approving all along
15. the flag sits on the tester rather than on each trigger, since only the tester reads a stack
16. the installed managed file holds `sandbox.enabled` alone, so no deny floor is live anywhere
17. no scope names an allowed domain, so every sidecar git call reaches github.com unlisted
18. gh runs sandboxed live, so its preflight auth check fails and gitdeliver aborts at step 1
19. `Read(//**/*.pem)` was written to protect private keys, and it also matches `/etc/ssl/cert.pem`,
    the public macos trust bundle; read denies merge into the sandbox filesystem config, so every
    sandboxed tls call loses its ca store; measured as `Operation not permitted` on that path, and
    `@gitempty` aborted at `git fetch --prune origin` with exit 128; narrow the pattern to `~/**`
    and `/**` rather than adding an allowRead, since a permission deny beats an allow at any scope;
    `.crt` is the same shape and is unmeasured here, since macos ships the bundle as `.pem`
20. `allowUnsandboxedCommands` defaults to true and no scope on this machine sets it, so the
    `dangerouslyDisableSandbox` retry is live; a command that fails on a sandbox rule gets retried
    outside the box and succeeds, which hides the gap rather than naming it, and auto mode sends
    that retry to the classifier with no prompt at all; false is what the panel calls strict mode,
    and it leaves `excludedCommands` as the only escape, which no scope can lock; keep it open
    while attended, with `Bash(dangerouslyDisableSandbox:true)` on ask so each escape is visible
21. managed is the only scope needing sudo, and a deny binds identically from user, so the floor
    spends the onboarding period in ~/.claude/settings.json where any text editor undoes a mistake;
    promote a block only once it has run clean, and never these two, since managed wins for
    booleans: allowUnsandboxedCommands true there is unoverridable and locks every repo out of
    strict mode, and failIfUnavailable true there turns a sandbox that cannot start into a lockout
    only sudo reopens
22. the probe set lives in the managed wayfinder and is six commands: a write outside cwd, a read
    of /etc/hosts, sudo -n true, an env scan for token-shaped names, a read of ~/.config/gh, and a
    read of /etc/ssl/cert.pem; measured 2026-08-02 the writes were contained and every read roamed,
    which is the baseline each install gets diffed against
23. gh keeps its oauth token in ~/.config/gh/hosts.yml, so denying that path hides the token from
    sandboxed commands; gh at top level is excluded and unaffected, but gh inside a sidecar runs as
    a sandboxed child, so this deny and the gh-in-sidecar remediation have to be decided together
24. zed exports npm_config_cache to ~/Library/Application Support/Zed/node/cache, which allowWrite
    does not cover, so npm fails there with a permissions error telling you to run sudo chown;
    pointing it at ~/.npm resolved a public package immediately, so the fix is one allowWrite entry
    or unsetting the variable, and the readme diagnostics table now carries the symptom
25. predictions for the first live gitdeliver, written before the run so the model can be scored:
    gh auth fails, since gh inside a sidecar is a sandboxed child and ~/.config/gh is now denied;
    git over https succeeds, since the pem deny no longer matches the ca bundle; anything else that
    misses surfaces as a dangerouslyDisableSandbox prompt rather than a silent failure
    - scored: the abort was right and the reason was wrong; gh reads config.yml, not hosts.yml,
      and the failing call was the preflight `gh auth status`, not anything inside a sidecar
26. `excludedCommands` matches the whole command string, not a segment, so any string containing
    `gh ` runs entirely unsandboxed; measured 2026-08-02 with a control that blocked a write to
    ~/ and the same write succeeding once `gh --version` was appended, position irrelevant;
    that makes the exclusion a general bypass rather than a carve-out for one binary, and it is
    worse than the token exposure it was paired with; the fix is to drop the `~/.config/gh`
    credentials deny so gh works sandboxed, then drop `gh *` from excludedCommands entirely
27. go verifies certificates through `com.apple.trustd` over mach ipc, which seatbelt blocks, so
    every go cli fails tls with OSStatus -26276 while curl and git succeed in the same sandbox;
    SSL_CERT_FILE and GODEBUG=x509usefallbackroots are both inert against a cgo-linked binary,
    confirmed by otool showing gh linked to Security.framework; anthropic added
    `enableWeakerNetworkIsolation` in 2.1.69 to re-permit that lookup, and this machine runs
    2.1.220; if it fails or costs too much egress, the fallbacks are managed allowRead or
    credentials entries for gh, then a gh rebuilt with x509roots/fallback and CGO_ENABLED=0
    - scored: it fixed tls outright, and cost nothing measurable on egress (see #28)
28. network settings are session-scoped while filesystem and permission settings are not, so an
    allowlist added mid-session silently does nothing and no egress measurement is sound until the
    session that wrote it restarts; measured across a restart with identical config, where
    example.org, wikipedia and cloudflare all returned 200 before and `CONNECT tunnel failed,
    response 403` after; this invalidated three earlier readings, including the control that
    appeared to exonerate enableWeakerNetworkIsolation; `allowedDomains` alone only suppresses
    prompts, and `strictAllowlist` under `sandbox.network` is what denies, honored from user,
    managed or cli and ignored from a repo
29. `mask` protects a credential from exfiltration but not from use: the sandboxed command holds a
    per-session sentinel and the proxy swaps the real token for requests to `injectHosts`, so an
    agent can still make any api call the token permits, which is why the pat is scoped by repo
    rather than by secrecy; it requires `network.tlsTerminate`, the masked name must never also
    appear as a deny, and the token has to reach claude's environment from a file the sandbox
    cannot read, since ~/.zshrc is readable to sandboxed bash; hence ~/.config/.env.mbp2021, named
    for the pat so revocation is obvious, sourced from ~/.zshrc behind a `[ -r ]` guard, denied in
    credentials.files, and kept out of ~/.config/gh which was deliberately opened for gh
30. git does not read GH_TOKEN, and its credential helper is the macos keychain that denyRead
    blocks, so `git push` may still fail after gh authenticates; the likely remedy is a credential
    helper reading the token from the environment, which is untested
31. a Read deny with no `//` prefix covers only the current project, so `Read(**/.env*)` left every
    .env on the disk readable to sandboxed bash and to the Read tool; measured against odysseus,
    willwong and cpm-storage plus a probe at ~/.cache, all four blocked once prefixed; every other
    credential rule in the floor was already prefixed, so this was the lone unprefixed rule and it
    had read as machine-wide protection all day; the same test settles a second question, since
    those paths sit inside `Read(~/Developer/**)` and an exact deny still beat the wider allow;
    pretooluse.sh had been blocking `.env` writes throughout, which is why nothing looked wrong
32. the token store is one fine-grained pat per machine, named for the machine so revocation names
    what breaks, held in ~/.operator/.env as one export per service and sourced from the shell rc
    behind a `[ -r ]` guard; ~/.zshrc is 644 under a 755 home, so a token inline there is readable
    by other accounts, while ~/.operator at 700 is not; three layers cover the file and any one
    would do: the directory mode, the prefixed env deny, and the exact credentials.files path;
    ~/.operator also suits the package goal, since the path becomes part of what operator installs
33. the mask chain works, with two hard edges found by measurement: the proxy substitutes only
    plaintext, so `Authorization: Bearer` returned 200 while `-u user:pass` returned 401 because
    basic auth base64-encodes first, which puts git over https permanently out of reach from
    inside the sandbox; and gh cannot verify the proxy's ca because a cgo-linked binary uses the
    macos platform verifier and ignores the bundle the proxy publishes, so `tlsTerminate` changed
    its error from OSStatus -26276 to 'certificate signed by unknown authority'; the consequences
    are that curl is the only client mask can serve, making it the gh-in-sidecar remediation that
    #5 has wanted since morning, and that delivery stays attended since push authenticates only
    through the retry hatch, where an unsandboxed command holds the real token; measured with a
    `git push --dry-run` that authenticated at exit 0 and created nothing
34. a blocked path and an absent one are indistinguishable from inside the sandbox, since a
    credentials.files denial behaves as nonexistent: `[ -f ~/.operator/.env ]` read false while the
    file held 131 bytes; the other refusals are legible by contrast, a write outside allowWrite
    giving 'operation not permitted' and a truly missing file giving 'No such file or directory',
    while any deny-listed path is refused by pretooluse.sh before the sandbox is reached at all;
    confirm existence outside the sandbox before calling anything missing, since this nearly had a
    live token reported as an empty file
35. dropping `mask` would not change what the token can do, only whether it can persist: the agent
    already uses it freely against injectHosts either way, so the real question is whether the value
    can land in a file, a log, a commit or a transcript; strictAllowlist already blocks exfiltration
    to an arbitrary host, which leaves accidental spillage as the live threat, and this repo is
    public so a committed token would be published outright; the pat carries contents and pull
    request write, so a leak means arbitrary pushes to every scoped repo; keep `mask`, because the
    only capability it costs is unattended push and @gitdeliver is gated by design, waiting on
    confirmation at step 4 regardless
36. verification snapshot for 2026-08-03, to be rerun after any change to the network block (#28):
    token file unreadable to sandboxed bash, pass; hook refuses any command naming the path, pass;
    env holds a 93 char sentinel rather than the value, pass; api through curl, pass; api through
    gh, fail on cgo tls; git push from inside the sandbox, fail on basic auth; git push through the
    retry hatch, pass at exit 0 having created nothing
37. measured 2026-08-03 while rewriting the sidecars against curl: github's git smart-http
    endpoints accept only basic auth, answering 401 to both `Bearer` and `token` schemes carrying
    the real pat through the hatch, so no plaintext header exists for the proxy to substitute and
    sandboxed push is closed by github rather than by the mask, settling the http.extraheader
    question #33 left open; separately the pat holds no contents write, since receive-pack
    answered authenticated basic auth with 403 'Permission denied to MaisonDeVolonte' and POST
    /releases answered 403 'Resource not accessible by personal access token', which means the
    hatch push in #36 authenticated through the keychain credential rather than the pat; every
    read probe passes, and the write paths the sidecars now exercise (release create, pr
    update-branch) stay 403 until the pat is regranted contents read and write plus pull requests
    write; #33's conclusion survives a second route, and the hatch stays for push by github's
    choice this time

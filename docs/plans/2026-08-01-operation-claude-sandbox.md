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
- [ ] decide the gh-in-sidecar remediation pattern
- [ ] grow corpus.tsv with argument-bearing sidecar calls and cat .env
- [x] validate the tester against gitdeliver, then against all 28 scripts (see #16)
- [ ] rerun the tester with the four templates staged as the stack, before installing them

### 7. Install and verify the live stack
- [ ] replace the stub managed file, which carries enabled and nothing else (see #16)
- [ ] name github.com and the npm registry in the live project file (see #17)
- [ ] restore the gh exclusion to the live project file; without it @gitdeliver cannot run (see #18)
- [ ] confirm the resolved config in the sandbox panel
- [ ] copy the user, project, and local files into place
- [ ] confirm gh still reaches the api with the domain allowlist enforcing (see #9)
- [ ] run gitdeliver end to end under the full stack
- [ ] run the tester against ownershive's project and local files (see #12)
- [ ] restore the npx ask to the live project file, which has never carried one (see #14)
- [ ] rerun permissions.sh and triage what changed
- [x] rebuild the readme deny section as a managed half and a project half
- [ ] add a readme allow section once the live stack shows what actually merged

### Deferred Work
- [ ] fix wayfinders.sh crashing when a path holds no eligible files
- [ ] decide whether the node deletes belong in system rather than execution
- [ ] build the tier 3 dynamic harness on sandbox-runtime with a scratch remote
- [ ] add an add-to-ask action to the plans.sh vocabulary
- [ ] preflight gh and jq, the two binaries macos does not ship
- [ ] carve the memory directory out of the deny list or accept no cross-session memory
- [ ] create AGENTS.md or repoint its 51 references

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
| 7. install and verify | 5 | 6 | 1 | see #7 |

### Permissions
suggested rules to set in order for agents to work reliably:

| rule | layer | scope | suggestion |
|---|---|---|---|
| 1. `Bash(AGENTS/security/*.sh*)` | permissions | project | add to allow |
| 2. `github.com` | sandbox domain | project | add to allowedDomains |
| 3. `registry.npmjs.org` | sandbox domain | project | add to allowedDomains |
| 4. `~/Library/Caches/pnpm` | sandbox filesystem | user | add to allowWrite |

#### Explanations
1. quoted from the project template; the live file lacks it, so tester runs prompt until stage 7
2. quoted from the project template; sidecar git fetch and push resolve there
3. quoted from the project template; future package installs resolve there
4. quoted from the user template; pnpm writes its cache outside cwd on every run

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

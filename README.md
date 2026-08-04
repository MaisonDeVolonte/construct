# AGENTS
**secure agentic coding infra: sandboxed automations, workflows, and conventions**

- **deterministic automations:** workflows are markdown prompts; bash sidecars do exact work 
- **machine-checked templates:** conventions are markdown guides; bash sidecars verify conformance
- **chat-native triggers:** @triggers work in any project; bash sidecars are project agnostic
- **cross-session memory:** context is seeded with docs and logs; bash hooks enforce compliance
- **built-in security suite:** auditable security and settings; diagnostics run across scopes
- **gated by default:** destructive commands are blocked entirely; permissions force prompts
- **centralized configuration:** improvements are fast and easy; symlinks sync across projects
- **zero dependencies:** bash, git, and jq only; nothing to build or install
- **easy opt-out:** symlinks are easy to delete; nothing to revert or uninstall
> *requires: claude code, bash, git, jq; [MIT License](LICENSE)*

## Installation (MacOS)

### 1. basic setup (5 mins)
- [ ] clone the repo (somewhere permanent):
  - [ ] `git clone https://github.com/MaisonDeVolonte/operator.git ~/Developer/operator`
- [ ] symlink from project (gitignored):
  - [ ] `ln -s ~/Developer/operator/README.md AGENTS.md`
  - [ ] `ln -s ~/Developer/operator/AGENTS AGENTS`

### 2. sandbox setup and testing (optional, highly recommended, ~30 mins)
- [ ] copy settings.user.json to `~/.claude/settings.json`
  - [ ] run `/sandbox`, and make sure sandbox is enabled
  - [ ] add package-manager caches to `sandbox.filesystem.allowWrite`
  - [ ] add deny rules for each `env | grep -iE 'key|token|secret'` to `sandbox.credentials.envVars`
  - [ ] make a secure directory for your keys: `mkdir -p ~/.operator && chmod 700 ~/.operator`
  - [ ] add non-exposed credentials to `~/.operator/.env` (e.g. `export GH_TOKEN="github_pat_123abc"`)
  - [ ] add deny rule for `~/.operator/.env` to `sandbox.credentials.files`
  - [ ] add mask and injectHosts rules for each `~/.operator/.env` export to `sandbox.credentials.envVars`
  - [ ] add each injectHosts host to `sandbox.network.allowedDomains`
  - [ ] append `[ -r ~/.operator/.env ] && source ~/.operator/.env` to `~/.zshrc`
  - [ ] restart editor and ask claude to run `echo $GH_TOKEN` and confirm a sentinel (never the token)
- [ ] copy settings.project.json to your project's `.claude/settings.json`
- [ ] copy settings.local.json to your project's `.claude/settings.local.json` (gitignore it)
- [ ] run `@settingsaudit`

### 3. managed sandbox and lockdown (optional, requires sudo, 5 mins)
- [ ] make the managed claude code directory `sudo mkdir -p '/Library/Application Support/ClaudeCode'`
- [ ] sudo copy settings.managed.json to `/Library/Application Support/ClaudeCode/managed-settings.json`
- [ ] run `@settingsaudit`

## Workflows
- DEFAULT posture is READ-ONLY
- DO NOT write code, edit files, or run commands without explicit approval

### Hooks
> each hook script can be customized to your workflow (see `AGENTS/hooks/`)
- [sessionstart](AGENTS/hooks/sessionstart.sh): injects the README and the two most recent log files into context
- [pretooluse](AGENTS/hooks/pretooluse.sh): failover for the committed deny list, reading the whole command string
- [posttooluse](AGENTS/hooks/posttooluse.sh): lints, then reports comment and wayfinder findings, never blocking
- [taskcreated](AGENTS/hooks/taskcreated.sh): nudges a new thread when a task is unrelated to the last one, advisory only
- [taskcompleted](AGENTS/hooks/taskcompleted.sh): blocks the turn to make the agent note the day's log
- [stop](AGENTS/hooks/stop.sh): every hour, saves notes and prompts, then synthesizes the day's log

### Git
> each pairs with a matching `.sh` sidecar that runs the automation (see `AGENTS/git/`)
- [@gitaudit](AGENTS/git/gitaudit.md): READ-ONLY; diagnostics, triage, report, summary, tasks (saved to file)
- [@gitbrutal](AGENTS/git/gitbrutal.md): READ-ONLY; brutally honest code review, progress report (saved to file)
- [@gitcontinue](AGENTS/git/gitcontinue.md): SAFE; stash, sync, and pop
- [@gitdeliver](AGENTS/git/gitdeliver.md): GATED; branch, atomically stage, commit, push, pr, watch
- [@gitempty](AGENTS/git/gitempty.md): GATED; prune, stash, fast-forward, restore, and hand over branch deletes
- [@gitfresh](AGENTS/git/gitfresh.md): GATED; stash, fetch, and hand over hard reset and branch deletes
- [@gitgud](AGENTS/git/gitgud.md): SAFE; query branch delta, merge remote main into it, and run fresh CI
- [@githappy](AGENTS/git/githappy.md): RELEASE; bumps version, adds tag, merges to production, and release notes
- [@gitinsights](AGENTS/git/gitinsights.md): READ-ONLY; verifies references, scans logs and codebase (saved to file)

### Templates
> each pairs with a matching `.sh` sidecar that verifies conformance (see `AGENTS/templates/`)
- [audits](AGENTS/templates/audits.md): via @gitaudit; appends findings and resolutions
- [brutal](AGENTS/templates/brutal.md): via @gitbrutal; adversarial graded scorecards
- [comments](AGENTS/templates/comments.md): via posttooluse.sh; inline comment shape
- [git](AGENTS/templates/git.md): via @git*; standardized trigger and sidecar shapes
- [graphs](AGENTS/templates/graphs.md): via @graphspec; writes graph spec prompt files
- [insights](AGENTS/templates/insights.md): via @gitinsights; searches repo for opportunities
- [logs](AGENTS/templates/logs.md): via @logthread, @lognote and @logsynth; maintains agent logs
- [plans](AGENTS/templates/plans.md): via @graphspec --execute; detailed fanout plan generation
- [study](AGENTS/templates/study.md): via @studyguide; writes detailed retrospective with graded quiz
- [wayfinders](AGENTS/templates/wayfinders.md): via posttooluse.sh; file header shape

### Tests
- `test what you deploy`: a passing local run is not a shipped artifact
- `run the build first`: a dev build ships debug data that the production build strips
- `kill the port`: a process still bound to it serves the build it started with
- `assert on a file the change wrote`: an unchanged hash proves nothing
- `print the value`: when the result contradicts the code, see what the code actually got
- `look at the bytes`: encrypted stores, binary files, and truncated reads all grep as empty

## Conventions
> `@retardify` applies all conventions in this section to target files or code:
- rename the file if its casing/extension violates `Files`
- resync the `Wayfinders` @description/@see with the file as it now stands
- reorder imports/exports per `Modules` order
- rewrite or prune `Comments` that explain how instead of why
- apply mechanical `Code` rewrites (e.g. ternaries → named-boolean guards)
- user gate logic changes that would trade away real information
- verify live before/after via tsc, tests, builds etc
- stop once further changes are diminishing returns

### Files
- `PascalCase.tsx` — ui-rendering components
- `camelCase.tsx` — logic and behavior components
- `camelCase.ts` — utilities and helpers
- `MatchCase.css` — co-located css matches its counterpart
- `kebab-case.css` — general/global css

### Wayfinders
```javascript
/**
 * ====================================================
 * @file AGENTS.md - jsdoc wayfinding header guidelines
 * ====================================================
 * @description
 * - automatically add this block to executable files (js, ts, tsx, jsx) not ignored by eslint.config.mjs
 * - can be triggered manually via @wayfind
 * - continuously update tags to reflect the file's contents, purpose, and dependencies
 *   - @file: the filename - short, specific title
 *   - @description: - hyphen delimited list of single clause descriptions, avoid wrapping text
 *   - @see: comma, separated, list, of, ALL, related, internal, files
 * - write maximally concise, shorthand, lowercase english, favoring legibility over completeness
 * - read this block to understand the file's context and boundaries before modifying it
 * @see AGENTS/, .claude/, eslint.config.mjs
 */
```

### Modules
- `external` packages (ordered alphabetically)
- `webflow` components (ordered by appearance)
- `internal` @/always/aliased/first-party/code
  - `data/files`
  - `config/schemas`
  - `ui/components`
  - `css` (ordered by cascade specificity)
- `reexported` module bindings
- `exported` bindings
  - `exported values`
  - `internal values`
  - `types`
  - `functions`

*example:*
```typescript
import { fetchFooCache } from "some-lib";
import type { FooConfig } from "some-lib";

import { getFoo } from "@/utilities/foo";
import type { FooBarShape } from "@/utilities/foobar";
import { FOO_URL, FOO_API_KEY } from "@/config/foobar";
import FooWidget from "@/modules/foo/Widget";
import "@/modules/foo/Widget.css";

export { helperFn } from "@/utilities/shared";

export const FOO_TAG = "foo-tag";
export const FOO_LIST = ["a", "b", "c"];

const FOO_TIMER = 3600;

export type FooNode = { path: string; type: string };

export async function getFoo(): Promise<FooNode[]> { return []; }
```

### Comments
- write comments sparingly and with intention, focusing on `why` code exists vs `how` it works
- refactoring code to be more intuitively legible is favorable over superfluous commenting
- use primarily inline comments written in maximally concise, clear, shorthand lowercase english
- including type hints at the end of `// comments — boolean` is helpful
- if a file is really long, consider adding header comments to break it up into sections:
  `// SECTION TITLE `

### Code
- `retard-maxx` like a jr-engineer who does everything the long, extremely boring way
- `simplify` logic over advanced, deeply nested, or overly efficient abstractions
- `separate` files or functions that do more than one thing, where practical
- `sequence` logic from top to bottom in order of state, definitions, guards, then execution
- `name` things using clear, concise, intuitively understood language
- `linebreaks` are to separate distinct conceptual blocks, not for single-line statements
- `first principles` such as DRY, SoC, POLA, etc are a vibe; RDD, WTF, WET, etc are not a vibe

*example:*
```typescript
// 1. global constants
const IS_AGENT = true;

type Requirement = {
  rawCode: string;
  badHabits: string[];
  nestingDepth: number;
  isDuplicated: boolean;
  isSurprising: boolean;
};

export function writeCode(requirements: Requirement[], request: string) {
  // 2. hoisted state
  const maxNesting = 2;
  let finalSolution = "";

  // 3. defined helpers
  function keepItSimple(req: Requirement) {
    if (req.rawCode.includes("?")) {
      const ternaryCount = (req.rawCode.match(/\?/g) || []).length;
      if (ternaryCount > 1) throw new Error("use an if-statement");
    }
    if (req.rawCode.includes(".reduce(")) throw new Error("use a for/forEach loop");
    if (req.rawCode.includes("\n\n\n")) throw new Error("use empty lines sparingly");
    if (req.nestingDepth > maxNesting) throw new Error("are you building a pyramid?");

    return true;
  }

  function respectFirstPrinciples(req: Requirement) {
    if (req.isDuplicated) throw new Error("extract to a helper");
    if (req.isSurprising) throw new Error("make it boring and obvious");
  }

  function punishAgent(variables: string[]) {
    if (!IS_AGENT) return;

    variables.forEach(variableName => {
      if (["e", "idx", "el", "cb"].includes(variableName)) {
        throw new Error("i get it, just spell it out please");
      }
      const charCount = variableName.length;
      const wordCount = variableName.split(/(?=[A-Z])/).length;
      if (charCount > 25 || wordCount > 4) {
        throw new Error(`'${variableName}' is not very helpful`);
      }
    });
  }

  // 4. main logic & execution
  if (!request) return finalSolution;

  requirements.forEach(req => {
    punishAgent(req.badHabits);
    respectFirstPrinciples(req);

    if (keepItSimple(req)) finalSolution += req.rawCode;
  });

  return finalSolution;
}
```

## Settings
> inspired by: 
> [Hardening Cheatsheet](https://dev.to/riotaro/hardening-cheatsheet-for-claude-codes-settingsjson-20lk),
> [Settings Reference](https://claudeguide.io/claude-code-settings-json-reference),
> [Permissions Guide](https://www.claudedirectory.org/blog/claude-code-permissions-guide)
> (see `AGENTS/settings/`)

### Authoring
> rules match strings, not commands (see `AGENTS/settings/settings.authoring.md`)
- spaces are load-bearing: `Bash(ls *)` matches `ls -la` but not `lsof`; `Bash(ls*)` matches both
- a trailing `*` is what matches arguments: `Bash(x.sh)` misses `x.sh --flag`, `Bash(x.sh*)` holds
- a `//` comment in a settings file voids every rule in it, silently

### Scopes
> each pairs with a matching `.json` file with all baseline settings (see `AGENTS/settings/`)
- [settings.cli.md](AGENTS/settings/settings.cli.md): one session, no file
- [settings.local.md](AGENTS/settings/settings.local.md): this repo, just you
- [settings.project.md](AGENTS/settings/settings.project.md): this repo, committed
- [settings.user.md](AGENTS/settings/settings.user.md): every repo, just you
- [settings.managed.md](AGENTS/settings/settings.managed.md): this machine, sudo
```
┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ ┌────────────────────────────────────────────────────────────────────┐ ┃
┃ │ ┌────────────────────────────────────────────────────────────────┐ │ ┃
┃ │ │ ┌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┐ │ │ ┃
┃ │ │ ┆ ┌┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┐ ┆ │ │ ┃
┃ │ │ ┆ ┊ cli: claude --settings                                 ┊ ┆ │ │ ┃
┃ │ │ ┆ ┊ "does this help me, in this session only?"             ┊ ┆ │ │ ┃
┃ │ │ ┆ └┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┘ ┆ │ │ ┃
┃ │ │ ┆ local: .claude/settings.local.json                         ┆ │ │ ┃
┃ │ │ ┆ "does this help only me, only in this project?"            ┆ │ │ ┃
┃ │ │ └╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┘ │ │ ┃
┃ │ │ project: .claude/settings.json                                 │ │ ┃
┃ │ │ "does this help everyone working in this project?"             │ │ ┃
┃ │ └────────────────────────────────────────────────────────────────┘ │ ┃
┃ │ user: ~/.claude/settings.json                                      │ ┃
┃ │ "does this help me across all projects in my user profile?"        │ ┃
┃ └────────────────────────────────────────────────────────────────────┘ ┃
┃ managed: /Library/Application Support/ClaudeCode/managed-settings.json ┃
┃ "does this protect everyone on this machine, long term?"               ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
```

### Auditing
> policy and its verification share one folder (see `AGENTS/settings/`)
- [@settingsaudit](AGENTS/settings/settingsaudit.md): READ-ONLY; audits the stack, probes it live (saved to file)
- [corpus](AGENTS/settings/corpus.tsv): labeled command corpus for audits; never executed
- [permissions.sh](AGENTS/settings/permissions.sh): replays the corpus then audits the settings rules
- [scopes.sh](AGENTS/settings/scopes.sh): tests a workflow against the merged scope stack
- [secrets.sh](AGENTS/settings/secrets.sh): shared credential patterns, used in every template sidecar

### Sandboxing
```
sandbox.allowUnsandboxedCommands

true   ●───○  TEST MODE:   commands that fail are retried outside the sandbox
              recommended: permissions.ask ["Bash(dangerouslyDisableSandbox:true)"]

false  ○───●  STRICT MODE: commands that fail are not retried at all
              recommended: sandbox.excludedCommands ["your *", "* commands"]
```
- sandboxing on macos uses the built-in `seatbelt` framework (kernel) for enforcement
- sandboxed commands cannot write `settings.json`, at any scope (see #12)
  - the same protection binds git: a branch switch cannot revert a delivered `.claude/settings.json`
  - so a delivery touching it strands a modified copy, and the post-merge pull needs a hatch restore
  - confirm the copy matches origin first: `git diff origin/main -- .claude/settings.json`
- sandbox is enabled for every scope (managed, cli, user, project, local)
- `failIfUnavailable`: default false warns and runs unsandboxed; true refuses to start
- sandbox-incompatible commands listed in anthropic docs: `gh`, `gcloud`, `terraform`, `docker`, `watchman`
  - `gh` reproduces the warning: cgo verifies via the platform verifier, so no ca env var reaches it
  - `enableWeakerNetworkIsolation` restores the trustd lookup it needs, correcting #13
- read-only bash commands are allowed by default (fixed, gated with deny or ask):
  - `ls`, `cat`, `echo`, `pwd`, `head`, `tail`, `grep`, `find`, `wc`, `which`, `diff`, `stat`, `du`, `cd`, and read-only forms of `git`

### Tool Denies
> any scope may add a deny, none may remove another's (see settings.user.json)
- `policy`: the settings, and the hooks and sidecars that enforce them
- `system`: root, disk formatting, recursive delete, ownership rewrite
- `execution`: eval, inline interpreters, curl-to-shell, node filesystem deletes
- `remote`: repo or release deletes, identity or secret changes, force or ref deletes
- `data`: database drops, migration resets
- `history`: filter-branch, force branch ops, hard reset, clean, stash drops
- `credentials`: env files, keys, certs, credential stores, shell history — every verb, not just read
- `persistence`: hooksPath, git aliases, launchctl, osascript, defaults write, shell rc files
- `keychain`: the `security` cli, which reaches keychaind rather than the files denyRead covers
- `exfiltration`: nc, ncat, socat, scp
- `publish`: npm/pnpm/yarn publish, docker push
- `infrastructure`: s3 deletes, kubectl deletes, terraform destroy
- `generated`: project scope only, being repo-shaped; a clone prunes what it does not have

### Tool Asks
> ask beats allow from any scope, so user scope alone is enough (see `AGENTS/settings/settings.user.md`)
- `escape`, `sidecars`, `runners`, `execution` — one-shot runners and anything the sandbox cannot contain

### Domain Allows
> unlisted hosts prompt, denied hosts refuse, and `strictAllowlist` turns prompts into refusals (see #17)
- five named hosts: github, the npm registry, and the claude docs (see `AGENTS/settings/settings.user.md`)
- project repeats user verbatim, so the egress travels with a clone

### Credentials
> `sandbox.credentials` hides secrets from sandboxed bash only; Read/Edit/Write need a permission rule
- `files` refuses reads, `envVars` unsets, `mask` swaps in a sentinel the proxy substitutes back
- `mask` stops a token persisting, never stops it being spent (see `AGENTS/settings/settings.user.md`)

### Keys
> one token per machine, named for the machine, so revoking it tells you exactly what breaks
- a fine-grained pat, held in `~/.operator/.env`, one `export` per service
- a lost laptop then revokes one credential instead of every project's access
- user-owned throughout, so no sudo to read, edit, or rotate
- `mask` stops the token leaving, never stops it being used, so the pat's scope is the real limit
- adding a service is one more `export`, plus a matching `mask` or `deny` entry

| layer                | what it stops                       |
|----------------------|-------------------------------------|
| `~/.operator` at 700 | every other account on the machine  |
| `Read(//**/.env*)`   | the Read tool, and sandboxed bash   |
| `credentials.files`  | sandboxed bash reading the file     |
| `pretooluse.sh`      | any command naming a denied path    |
| `mask`               | the real value entering the sandbox |

> how to install a personal access token:
- [ ] make a secure directory for your keys: `mkdir -p ~/.operator && chmod 700 ~/.operator`
- [ ] add non-exposed credentials to `~/.operator/.env` (e.g. `export GH_TOKEN="github_pat_123abc"`)
- [ ] add deny rule for `~/.operator/.env` to `sandbox.credentials.files`
- [ ] add mask and injectHosts rules for each `~/.operator/.env` export to `sandbox.credentials.envVars`
- [ ] add each injectHosts host to `sandbox.network.allowedDomains`
- [ ] append `[ -r ~/.operator/.env ] && source ~/.operator/.env` to `~/.zshrc`
- [ ] restart editor and ask claude to run `echo $GH_TOKEN` and confirm a sentinel (never the token)

#### GitHub
> `GH_TOKEN` is masked to `api.github.com` and `github.com` (`GITHUB_TOKEN` stays denied)

| operation           | sandboxed | why                                            |
|---------------------|-----------|------------------------------------------------|
| api through curl    | works     | honors the proxy ca, and Bearer is plaintext   |
| api through gh      | never     | cgo verifies via the platform verifier         |
| git fetch, ls-remote| works     | libcurl honors the proxy ca                    |
| git push            | never     | basic auth base64s the sentinel out of reach   |
| git push, hatch     | works     | unsandboxed commands hold the real token       |

- curl is the only client `mask` can serve, so it replaces gh for every api call in a sidecar
- gh fails whatever the config: no env var reaches a cgo-linked verifier, and excluding it
  unsandboxes the entire command string rather than just gh
- push stays on the retry hatch by choice, since dropping `mask` to gain it would put the real
  token in every sandboxed command for a capability `@gitdeliver` is gated against anyway
- revisit only if anthropic ships a non-cgo gh, or the proxy learns to substitute inside base64
- an unlisted github host is refused, and `*.github.com` is avoided on purpose since it reaches gist
- upstream issues to watch, since a shipped fix moves rows in the table above (checked 2026-08-03):
  - [#26466](https://github.com/anthropics/claude-code/issues/26466): the liveliest go-tls thread; gh fails through the built-in proxy
  - [#77333](https://github.com/anthropics/claude-code/issues/77333): the same OSStatus -26276 measured here, reported on tahoe
  - [#82793](https://github.com/anthropics/claude-code/issues/82793): allowMachLookup unwired, so enableWeakerNetworkIsolation stays the only go-tls fix
  - [#81157](https://github.com/anthropics/claude-code/issues/81157): an excludedCommands glob unsandboxes the whole invocation, matching what was measured here
  - [#82109](https://github.com/anthropics/claude-code/issues/82109): excludedCommands also skips commands inside shell loops, more reason it stays dropped
  - [#81211](https://github.com/anthropics/claude-code/issues/81211): feature ask for domain-scoped credential injection, the conversation nearest to `mask`
  - [#82255](https://github.com/anthropics/claude-code/issues/82255): the macos proxy drops git-over-ssh credentials; a second push path if it lands

### Enforcement
- sandbox is for containing, permissions are for denying
- both must pass: an allow rule opens no sandbox path, and an open path grants no permission
- the `sees` row is what bites: permissions trust the whole script, sandbox polices its children
- sandboxed commands never consult allow lists; deny and ask still apply

|          | permissions        | sandbox                   |
|----------|--------------------|---------------------------|
| governs  | tool               | bash (and children)       |
| active   | always             | when sandboxed            |
| layers   | one                | filesystem and domain     |
| runs     | before             | during (at kernel)        |
| sees     | string             | script (and children)     |
| resolves | deny → ask → allow | path specificity          |
| denies   | a clean refusal    | 'Operation not permitted' |
| prompts  | ask or no match    | unlisted domains          |

### Precedence
- verdict: hook deny → deny → ask → hook allow → allow (see #1 - #3, #5)
- scope: managed → cli → local → project → user; scalars override, arrays merge (see #4)

| rule family        | resolves by                            | see            |
|--------------------|----------------------------------------|----------------|
| permissions        | category order, first match wins       | #6 - #8        |
| sandbox filesystem | narrowest path, allow or deny          | #12, #14 - #16 |
| sandbox domain     | denied beats allowed, unlisted prompts | #14, #17       |
| additive lists     | no contest, every entry counts         | #18 - #19      |

- Read/Edit and WebFetch(domain:) `allows` also seed the sandbox (see #20 - #21)
- an always-allow grant is just an allow rule in local; deny still beats it (see #9 - #11)

### Misconceptions
- each assumes a simpler system than exists: one gate, one file, or one failure mode
- when a rule surprises you, the right column usually names the reason

| instinct                   | actually                            |
|----------------------------|-------------------------------------|
| more allows, more autonomy | sandboxed bash never reads them     |
| deny is allow's opposite   | deny wins from any scope, any depth |
| a block will prompt me     | files fail silently, domains prompt |
| settings.json is what runs | all scopes merge; check `/sandbox`  |
| managed is strictest       | managed is unoverridable            |
| rules see inside scripts   | permissions see one string per call |
| an allow makes it work     | the sandbox is a second gate        |
| excludedCommands is narrow | it unsandboxes the whole call       |
| a masked token is safe     | unreadable, still spendable         |
| a stray comment is cosmetic| it voids every rule in the file     |

### Diagnostics
- [permissions.sh](AGENTS/settings/permissions.sh) replays a corpus through the real hook and audits the live rules
- `/sandbox` prints the merged settings (source of truth)
- start from the symptom, since the layer that blocked a call is rarely the one you were watching

| symptom                      | layer                  | fix                                  |
|------------------------------|------------------------|--------------------------------------|
| 'Operation not permitted'    | sandbox filesystem     | allowWrite/allowRead (see #17)       |
| tool suggests `sudo chown`   | sandbox filesystem     | allowWrite the named path (see #17)  |
| prompt naming unlisted host  | sandbox domain         | allowedDomains (see #21)             |
| prompt for ordinary command  | permissions, no match  | add allow in project scope (see #6)  |
| blocked despite an allow     | permissions or hook    | grep for matching deny (see #1, #18) |
| tool missing from context    | permissions, bare deny | add tool specifier (see #7)          |
| runs by hand but .sh fails   | sandbox filesystem     | grant child commands (see #14)       |
| a setting that looks ignored | scope merge            | diff `/sandbox` config (see #4, #15) |
| a whole scope looks ignored  | invalid json           | `jq empty` the file; a comment voids it |
| sidecar prompts with a flag  | permissions, no match  | add the `*` tail so args match (see #6) |
| pull aborts on settings.json | sandbox filesystem     | confirm it matches origin, then restore and pull via the hatch |

### Sources

#### [Hooks (code.claude.com/docs/en/hooks)](https://code.claude.com/docs/en/hooks)
1. a PreToolUse hook can block a tool call, and no allow rule can override that block
2. it blocks by exiting 2, or by printing `permissionDecision: deny` and exiting 0
3. exit 1 does not block; a hook that crashes lets the call through

#### [Settings (code.claude.com/docs/en/settings)](https://code.claude.com/docs/en/settings)
4. managed wins outright; every array below merges across all scopes

#### [Permissions (code.claude.com/docs/en/permissions)](https://code.claude.com/docs/en/permissions)
5. a hook allow only skips the prompt; deny and ask still apply
6. specificity never reorders: `Bash(aws *)` deny beats `Bash(aws s3 ls)` allow
7. a bare tool deny (e.g. `Bash`) removes the tool from context entirely
8. covers every tool: bash, read, edit, webfetch, mcp, etc
9. always allow writes an allow rule into local, so any deny or ask still beats it
10. bash grants persist per repo and command; edit grants only last the session
11. approving a compound command saves one rule per subcommand, up to five

#### [Sandboxing (code.claude.com/docs/en/sandboxing)](https://code.claude.com/docs/en/sandboxing)
12. `filesystem.disabled` voids denyRead, credentials.files, and settings.json protection
13. `gh` commands successfully reached the api despite anthropic's sandbox warnings
14. both layers bind only sandboxed commands; excludedCommands escapes them
15. `allowManagedReadPathsOnly` honors managed `allowRead` only; denies still merge
16. `credentials.envVars` survives `filesystem.disabled`, since env scrubbing is not a file rule
17. unlisted domains prompt; file denials are silent, failing "Operation not permitted"
18. deny only narrows, so any scope may add one and none may remove another's
19. `excludedCommands` has no managed lock, so any scope can widen it
20. `Read` and `Edit` rules merge into the final sandbox filesystem config
21. `WebFetch(domain:)` allows join the bash allowlist; never the reverse

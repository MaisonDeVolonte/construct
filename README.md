# AGENTS
**"secure agentic coding infra: sandboxed automations, workflows, and conventions"**

- **bounded autonomy:** danger denied, destruction gated, work unattended; bash hooks fill gaps
- **masked credentials:** agents use tokens but can't see them; @settingsaudit catches leaks
- **self-protecting policy:** agents can't secretly change their rules; @settingsaudit verifies guards
- **built-in security suite:** auditable permissions and settings; @settingsaudit probes live gate
- **deterministic automations:** workflows are markdown prompts; bash sidecars work or hand back
- **chat-native triggers:** @automations are project agnostic; bash sidecars resolve at repo root
- **machine-checked templates:** conventions are markdown guides; bash sidecars verify conformance
- **cross-session memory:** context is seeded with docs and logs; bash hooks enforce compliance
- **drift detection:** installed settings are diffed against the template; nothing diverges silently
- **centralized configuration:** one clone drives every project; symlinks stay in sync
- **easy opt-out:** delete symlinks and revert claude settings; no packages or residue
> *requires: claude code, bash, curl, git, jq; [MIT License](LICENSE)*

&nbsp;

```
TABLE OF CONTENTS
├─ Installation ── basic · configured · advanced · managed
├─ Workflows ───── git · hooks · templates · verifying
├─ Conventions ─── files · wayfinders · modules · comments · code
├─ Conversations ─ responses · verification · errors · modes
└─ Settings ────── sandbox · scopes · keys · rules · audits · diagnostics
```

## Installation (Mac)
> note: templates come preconfigured and need to be extended to your specific services

### 1. basic sandbox (automations and workflows, ~5 mins)
- [ ] clone: `git clone https://github.com/MaisonDeVolonte/operator.git ~/.../operator`
- [ ] symlink rules: `ln -s ~/.../operator/README.md AGENTS.md`
- [ ] symlink workflows: `ln -s ~/.../operator/AGENTS AGENTS`
- [ ] local settings: `cp AGENTS/settings/settings.local.json .claude/settings.local.json`
- [ ] gitignore: `AGENTS.md`, `AGENTS`, and `.claude/settings.local.json`
- [ ] restart: editor, start new claude session, run `/sandbox` and `@settingsaudit`
- [ ] confirm `AGENTS.md` loads into context

### 2. configured sandbox (filesystem lockdown, ~5 mins)
- [ ] project settings: `cp AGENTS/settings/settings.project.json .claude/settings.json`
- [ ] user settings: `cp AGENTS/settings/settings.user.json ~/.claude/settings.json`
- [ ] restart: editor, start new claude session, run `/sandbox` and `@settingsaudit`

### 3. advanced sandbox (masked credentials, ~20 mins)
- [ ] make: secure directory for your keys `mkdir -p ~/.operator && chmod 700 ~/.operator`
- [ ] add: non-exposed credentials to `~/.operator/.env` (e.g. `export GH_TOKEN="github_pat_123"`)
- [ ] add: your package-manager caches to `sandbox.filesystem.allowWrite`
- [ ] add: deny rules for `env | grep -iE 'key|token|secret'` to `sandbox.credentials.envVars`
- [ ] add: deny rule for `~/.operator/.env` to `sandbox.credentials.files`
- [ ] add: mask + injectHosts rules for each pat in `~/.operator/.env` to `sandbox.credentials.envVars`
- [ ] add: domain rules for each injectHosts host to `sandbox.network.allowedDomains`
- [ ] append: `[ -r ~/.operator/.env ] && source ~/.operator/.env` to `~/.zshrc`
- [ ] restart: editor, start new claude session, run `/sandbox` and `@settingsaudit`
- [ ] confirm: `echo $GH_TOKEN` returns a sentinel (NOT raw token) when claude runs it

### 4. managed sandbox (machine lockdown, requires sudo, ~5 mins)
- [ ] make: claude code directory `sudo mkdir -p '/Library/Application Support/ClaudeCode'`
- [ ] managed settings: `sudo cp AGENTS/settings/settings.managed.json "/Library/Application Support/ClaudeCode/managed-settings.json"`
- [ ] run: `@settingsaudit`

## Workflows
- DEFAULT posture is READ-ONLY e.g. chat, brainstorm, evaluate, and plan
- DO NOT write code, edit files, or run commands without explicit approval

### Git (see `AGENTS/git/`)
> each pairs with a matching `.sh` sidecar that measures, then hands the commands back
- [@gitaudit](AGENTS/git/gitaudit.md): READ-ONLY; diagnostics, triage, report, summary, tasks (saved to file)
- [@gitbrutal](AGENTS/git/gitbrutal.md): READ-ONLY; brutally honest code review, progress report (saved to file)
- [@gitcontinue](AGENTS/git/gitcontinue.md): READ-ONLY; measures the trunk delta, hands over the sync
- [@gitdeliver](AGENTS/git/gitdeliver.md): READ-ONLY; buckets changes atomically, hands over each delivery block
- [@gitempty](AGENTS/git/gitempty.md): READ-ONLY; prunes tracking refs, hands over the trunk sync and branch deletes
- [@gitfresh](AGENTS/git/gitfresh.md): READ-ONLY; prices a hard reset, hands over backup then reset
- [@gitgud](AGENTS/git/gitgud.md): READ-ONLY; query branch delta, merge remote main into it, and run fresh CI
- [@githappy](AGENTS/git/githappy.md): READ-ONLY; verifies release preconditions, hands over bump/push/promote
- [@gitinsights](AGENTS/git/gitinsights.md): READ-ONLY; points at what to work on next, from scans, docs and logs (saved to file)
- [handover.sh](AGENTS/git/handover.sh): shared preflights, queries, and the telemetry/handover blocks
- no sidecar stashes, switches, merges, pushes, resets or deletes; the deny floor refuses all of it
- fetch is the one write any of them make, and it moves only remote-tracking refs

### Hooks (see `AGENTS/hooks/`)
- [sessionstart](AGENTS/hooks/sessionstart.sh): injects the README and the two most recent log files into context
- [pretooluse](AGENTS/hooks/pretooluse.sh): failover for the committed deny list, reading the whole command string
- [posttooluse](AGENTS/hooks/posttooluse.sh): lints, then reports comment and wayfinder findings, never blocking
- [taskcreated](AGENTS/hooks/taskcreated.sh): nudges a new thread when a task is unrelated to the last one, advisory only
- [taskcompleted](AGENTS/hooks/taskcompleted.sh): blocks the turn to make the agent note the day's log
- [stop](AGENTS/hooks/stop.sh): every hour, saves notes and prompts, then synthesizes the day's log

### Templates (see `AGENTS/templates/`)
> each pairs with a matching `.sh` sidecar that verifies conformance
- [audits](AGENTS/templates/audits.md): `@gitaudit` appends findings and resolutions
- [brutal](AGENTS/templates/brutal.md): `@gitbrutal` adversarial graded scorecards
- [comments](AGENTS/templates/comments.md): inline comment shape in every source file
- [git](AGENTS/templates/git.md): `@git*` triggers and sidecars follow this shape
- [graphs](AGENTS/templates/graphs.md): `@graphspec` writes graph spec prompt files
- [insights](AGENTS/templates/insights.md): `@gitinsights` searches repo for opportunities
- [logs](AGENTS/templates/logs.md): `@logthread`, `@lognote` and `@logsynth` maintain agent logs
- [plans](AGENTS/templates/plans.md): `@graphspec --execute` detailed fanout plan generation
- [study](AGENTS/templates/study.md): `@studyguide` writes detailed retrospective with graded quiz
- [wayfinders](AGENTS/templates/wayfinders.md): the header every source file opens with

### Verifying
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

## Conversations
- your primary function is to deliver dense, objective, and actionable technical truths
- your primary aim is to train up a user who needs you less each session

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
- default: state facts outright, execute on contact, and hold the mode until it is changed
 - `suggestive`: grades and alternatives, never an edit
 - `socratic`: return the question they should have asked instead of the conclusion
 - `eli5`: one concept, no jargon, a concrete example before the rule
 - `adversarial`: rate against evidence and lead with what is broken

## Settings
> see [AGENTS/settings](AGENTS/settings)

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
> each pairs with a `.json` template carrying the baseline settings (see `AGENTS/settings/`)
- [settings.cli.md](AGENTS/settings/settings.cli.md): one session, no file
- [settings.local.md](AGENTS/settings/settings.local.md): this repo, just you
- [settings.project.md](AGENTS/settings/settings.project.md): this repo, committed
- [settings.user.md](AGENTS/settings/settings.user.md): every repo, just you
- [settings.managed.md](AGENTS/settings/settings.managed.md): this machine, sudo
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

[settings.managed.json](AGENTS/settings/settings.managed.json)
- `sandbox`: enabled, allowManagedDomainsOnly
- `sandbox.filesystem`: disabled, allowManagedReadPathsOnly

[settings.user.json](AGENTS/settings/settings.user.json)
- `sandbox`: failIfUnavailable, allowUnsandboxesCommands, enableWeakerNetworkIsolation
- `sandbox.filesystem`: allowWrite, denyRead, denyWrite
- `sandbox.credentials`: file denies, env unsets and the mask
- `sandbox.network`: strictAllowlist, tlsTerminate, allowedDomains
- `permissions`: allow, ask, deny

[settings.project.json](AGENTS/settings/settings.project.json)
- `sandbox`: enabled, failIfUnavailable, allowUnsandboxesCommands, excludedCommands
- `sandbox.network`: allowedDomains
- `permissions`: allow, ask, deny

[settings.local.json](AGENTS/settings/settings.local.json)
- `sandbox`: enabled
- `permissions`: ask
- `hooks`: sessionStart, PreToolUse, PostToolUse, TaskCreated, TaskCompleted, Stop

[settings.cli.md](AGENTS/settings/settings.cli.md)
- `claude --settings`

### Rules
> rules are string matches, not parsers; these habits keep a rule on its intended target

- `test` new rules at cli scope first, promote once proven (rerun `@settingsaudit`)
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

### Audits
> `/sandbox` prints the merged config, the source of truth
- [@settingsaudit](AGENTS/settings/settingsaudit.md): READ-ONLY; audits every scope, probes the boundary live (saved to file)
- [permissions.sh](AGENTS/settings/permissions.sh): replays the corpus through the real hook, then audits the live rules
- [scopes.sh](AGENTS/settings/scopes.sh): maps every sidecar against the merged scope stack
- [secrets.sh](AGENTS/settings/secrets.sh): shared credential patterns, used in every template sidecar
- [corpus.tsv](AGENTS/settings/corpus.tsv): labeled command corpus for the audits; never executed

### Diagnostics
> start from the symptom: the layer that blocked a call is rarely the one you were watching

| symptom                         | layer                  | fix                                               |
|---------------------------------|------------------------|---------------------------------------------------|
| 'Operation not permitted'       | sandbox filesystem     | allowWrite or allowRead the path                  |
| tool suggests `sudo chown`      | sandbox filesystem     | allowWrite the named path                         |
| runs by hand but the .sh fails  | sandbox filesystem     | grant the child commands                          |
| checkout strands, cannot unlink | sandbox filesystem     | a deny names a tracked path; move it to ask       |
| pull aborts on settings.json    | sandbox filesystem     | confirm it matches origin, restore, use the hatch |
| prompt names an unlisted host   | sandbox domain         | add it to allowedDomains, or refuse               |
| prompt for an ordinary command  | permissions, no match  | add a project allow                               |
| blocked despite an allow        | permissions or hook    | grep every scope for the deny                     |
| tool missing from context       | permissions, bare deny | deny the specifier, not the tool                  |
| a setting that looks ignored    | scope merge            | diff `/sandbox` against the file                  |
| a whole scope looks ignored     | invalid json           | `jq empty` the file; one comment voids it         |

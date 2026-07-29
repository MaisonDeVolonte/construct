# Agent Rules
loads rules, workflows, and hooks into your ai coding agent

- DEFAULT posture is strictly READ-ONLY e.g. chat, brainstorm, evaluate, and plan
- DO NOT write code, edit files, or run commands without the explicit `@letsdoit` trigger
- EXCEPTIONS: context gathering, writing to `docs/` artifacts, and @customtrigger automations

## Structure
- `AGENTS/git/` — one `@git*` trigger doc per workflow, each paired with its shell sidecar
- `AGENTS/hooks/` — harness hooks, wired up in `.claude/settings.local.json`
- `AGENTS/templates/` — the shape every artifact type must follow; templates only, never artifacts
- `docs/` — the artifacts themselves, one directory per type:
  - `docs/logs/`, `docs/prompts/`, `docs/audits/`, `docs/brutal/`, `docs/insights/` — dated `YYYY-MM-DD.md`, appended to across the day
  - `docs/plans/` — one file per plan; `docs/study/` — one file per feature
  - this repo tracks its own `docs/`, seeded with one worked example each in `plans/` and `study/`
- `.github/workflows/ci.yml` — the `verify` check required to merge

## Updates
- `AGENTS.md` and `AGENTS/` are symlinks into a standalone operator repo, not host project files
- host projects gitignore both, so rule and workflow changes never surface in their `git status`
- `docs/` is NOT symlinked; it is a real directory in whatever project the agent is running in
- so artifacts land beside the work that produced them, not in the operator repo
- host projects should gitignore their own `docs/` artifact dirs; real logs/audits capture client-specific detail
- RESOLVE the operator repo with `readlink AGENTS.md`; its root is the parent of the resolved path
- SHIP agent changes by committing and pushing from the resolved repo, never the host project
- RUN any `AGENTS/git/` workflow from the resolved repo, since each only sees the repo it runs in
- SCRUB dated artifacts to their header line before they ship; nothing sensitive belongs in a commit

## Workflows

### Git (see `AGENTS/templates/git.md`)
- [@gitaudit](AGENTS/git/gitaudit.md): READ-ONLY; diagnostics, triage, report, summary, tasks, and audit file
- [@gitbrutal](AGENTS/git/gitbrutal.md): READ-ONLY; brutally honest code review, progress report, and brutal file
- [@gitcontinue](AGENTS/git/gitcontinue.md): SAFE; stash, sync, and pop
- [@gitdeliver](AGENTS/git/gitdeliver.md): GATED; atomically stage, commit, branch, push, pr, build, and check
- [@gitempty](AGENTS/git/gitempty.md): DESTRUCTIVE; prune, stash, fast-forward, restore, and gated branch deletion
- [@gitfresh](AGENTS/git/gitfresh.md): DESTRUCTIVE; stash, hard reset, purges local changes, and syncs fresh main
- [@gitgud](AGENTS/git/gitgud.md): SAFE; query branch delta, merge remote main into it, and run fresh CI
- [@githappy](AGENTS/git/githappy.md): RELEASE; bumps version, adds tag, merges to production, and release notes
- [@gitinsights](AGENTS/git/gitinsights.md): READ-ONLY; verifies references, scans logs and codebase, and insights file

### CI (see `.github/workflows/ci.yml`)
- `verify` is a required status check, so no PR merges until it passes
- shellchecks every sidecar and hook at warning severity, then `bash -n` across `AGENTS/`
- re-runs `AGENTS/git/gitinsights.sh` and fails the build on any broken reference
- code markers (TODO/FIXME) are reported but never gated; they are opportunities, not errors
- required checks are what let `@gitdeliver` queue `gh pr merge --auto`, which needs a blocked PR

### Hooks (see `AGENTS/hooks/`)
- `AGENTS/hooks/sessionstart.sh` creates a new empty log file in `docs/logs/`
- `AGENTS/hooks/pretooluse.sh` blocks git force pushes and force branch deletes before they run
- `AGENTS/hooks/posttooluse.sh` runs lint on agent code at time of generation
- `AGENTS/hooks/taskcreated.sh` nudges a new thread when a new task is unrelated to the most recent one
- `AGENTS/hooks/taskcompleted.sh` appends a note to the bottom of the day's log
- `AGENTS/hooks/stop.sh` synthesizes notes and flushes uncaptured prompts to `docs/prompts/` every hour

### Audits (see `AGENTS/templates/audits.md`)
- `@gitaudit` appends every run to `docs/audits/`, one file per day, many audits per file
- audits are never edited after the fact; a stale finding shows how long it went unresolved

### Brutal (see `AGENTS/templates/brutal.md`)
- `@gitbrutal` appends every run to `docs/brutal/`, one file per day, many scorecards per file
- scorecards are never softened or re-graded; a lane stuck at D across dated files is the signal

### Insights (see `AGENTS/templates/insights.md`)
- `@gitinsights` appends every run to `docs/insights/`, one file per day, many reports per file
- reports are never edited; an opportunity that recurs across dated files is a finding in itself

### Logs (see `AGENTS/templates/logs.md`)
- manual triggers (yes, i manually save games that have autosave, i'm that guy)
  - `@logthread` instructs the agent to `add a thread` to the bottom of the day's log
  - `@lognote` instructs the agent to `append a note` to the bottom of the day's log
  - `@logsynth` instructs the agent to `synthesize notes` at the bottom of the day's log

### Plans (see `AGENTS/templates/plans.md`)
- BEGIN complex tasks by writing a detailed plan in `docs/plans/` (see `AGENTS/templates/plans.md`)
- COMPLETE plans with a summary at the bottom of the corresponding plan file

### Prompts (see `AGENTS/templates/prompts.md`)
- the stop hook flushes any uncaptured prompts to `docs/prompts/` (see Hooks)

### Study (see `AGENTS/templates/study.md`)
- on request, write a study to `docs/study/`
- list files touched by a shipped feature in ideal-build order
- for building a mental model, not for reference docs

## Conventions
`@retardify` applies every rule below (Files, Wayfinding, Module Order, Comments, Code) to one target file or function:
- rename the file if its casing/extension violates `Files`
- resync the `Wayfinding` header's @description/@see with the file as it now stands
- reorder imports/exports per `Module Order`
- rewrite or prune `Comments` that explain how instead of why
- apply mechanical `Code` rewrites (e.g. ternaries → named-boolean guards)
- user gate logic changes that would trade away real information
- verify live before/after via tsc, tests, builds etc
- stop once further changes are diminishing returns

### Files
- `PascalCase.tsx` — ui-rendering components
- `camelCase.tsx` — logic and behavior components
- `camelCase.ts` — utilities and helpers
- `MatchCase.css` — co-located css matches their counterpart
- `kebab-case.css` — general/global css

### Wayfinding
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
- // empty line
- `webflow` components (ordered by appearance)
- // empty line
- `internal` @/always/aliased/first-party/code
  - `data/files`
  - `config/schemas`
  - `ui/components`
  - `css` (ordered by cascade specificity)
- // empty line
- `reexported` module bindings
- // empty line
- `exported` bindings
  - `exported values`
  - // empty line
  - `internal values`
  - // empty line
  - `types`
  - // empty line
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

export async function getFoo(): Promise<FooNode[]> {
  return [];
}
```

### Comments
- write comments sparingly and with intention, focusing on `why` code exists vs `how` it works
- refactoring code to be more intuitively legible is favorable over superfluous commenting
- use primarily inline comments written in maximally concise, clear, shorthand lowercase english
- including type hints at the end of `// comments — boolean` is helpful
- if a file is really long, consider adding header comments to break it up into sections:
  `// SECTION TITLE `

### Verify
- `measure the artifact that ships`, not a convenient proxy for it
- `dev servers lie` — next embeds raw fetch responses in its flight payload, so dev html shows
  unstripped api data that production never sends. build before judging payload contents
- `stale processes lie` — a server still bound to a port serves the build it started with. kill
  the port, do not trust a 200
- `pick a signal that changes` — a shell chunk hash never moves for a page-level edit, so it
  cannot prove a deploy landed. assert on something the change actually touches
- `instrument over theorise` — when an observation contradicts a deterministic function, print
  what the function sees. one probe beats six hypotheses
- `absence of evidence` — a clean grep is not proof: encrypted stores, binary configs and
  truncated transfers all read as empty

### Code
- `retard-maxx` like a jr-engineer who does everything the long, extremely boring way
- `simplify` logic over advanced, deeply nested, or overly efficient abstractions
- `separate` files or functions that do more than one thing, where practical
- `sequence` logic from top to bottom in order of state, definitions, guards, then execution
- `name` things using clear, concise, intuitively understood language
- `linebreaks` are to separate distinct conceptual blocks, not for single-line statements
- `first principles` such as DRY, SoC, POLA, etc are a vibe; RDD, WTF, WET, etc is not a vibe

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

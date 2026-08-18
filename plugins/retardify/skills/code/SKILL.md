---
name: code
license: MIT
compatibility: requires bash, git
description: code-legibility linter run by PostToolUse or via <path> argument (saves audits to .construct/)
argument-hint: "[--help] <path> [--test]"
when_to_use: "editing code, PostToolUse warnings, or when asked to review code"
paths: "**/*.ts, **/*.tsx, **/*.js, **/*.jsx, **/*.mjs, **/*.cjs, **/*.sh, **/*.py, **/*.rb, **/*.go, **/*.rs"
metadata:
  artifact: .construct/retardify/code/
---

**maximally legible code:** ensures you're able to keep up with the codebase
- `logic-only` refactors since `/retardify:file` already owns the frame around it
- `retard-maxxes` like a jr-engineer who does everything the long, extremely boring way
- `simplifies` logic instead of advanced, deeply nested, or overly efficient abstractions
- `separates` files or functions that do more than one thing, where practical
- `sequences` logic from top to bottom in order of state, definitions, guards, then execution
- `names` things using clear, concise, intuitively understood language
- `linebreaks` separate distinct conceptual blocks, not single-line statements
- `first principles` such as DRY, SoC, POLA, etc are a vibe; RDD, WTF, WET, etc are not a vibe

<details>
<summary>example:</summary>

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

</details>

# Instructions

## Telemetry
```!
if [ -n "$ARGUMENTS" ];
then "${CLAUDE_PLUGIN_ROOT}"/skills/code/code.sh $ARGUMENTS; echo "sidecar exit: $?"
else echo "no path given, so nothing ran; the hook lints every write, so apply the rules below"; fi
```
- `help: requested` → the run was refused before it started; `## Help` below is the whole turn
- this already ran; never re-issue it, and never a bare `code.sh`, which grades one file only
- `fail (sidecar exit > 0)` → report the raw terminal error inside a markdown code block
- `success` → take `audit_file`, then follow VERIFY below, fixing every finding

## Mechanics
> the falsifiable limits the sidecar grades, one label each

| label | the rule it holds |
|---|---|
| `ternary` | one ternary per expression; a second is an if-statement wearing a costume |
| `reduce` | no `.reduce(` where a for or forEach loop says the same thing plainer |
| `nesting` | nesting caps at 2 levels; a third is a pyramid, so a guard or a helper flattens it |
| `blank_run` | one blank line between blocks, never two |
| `short_name` | no `e`, `idx`, `el`, `cb`; spell it out |
| `long_name` | a name caps at 25 characters and 4 words |

- `ternary`, `reduce` and `short_name` are js idioms, so they run on the js family only
- the other three run on every graded language, since depth and naming travel everywhere
- a comment or a full-line marker is skipped, so prose never trips a code rule

## First Principles
> what no script can judge and what the sidecar prints instead

- vibes:
  - `DRY` don't repeat yourself: if a block is written more than twice, extract it
  - `SoC` separation of concerns: if a file does more than one thing, split it
  - `POLA` least astonishment: if the obvious reading of the code is wrong, refactor it
- NOT vibes:
  - `RDD` resume-driven development: if a reader says 'he must be a senior dev', it's wrong
  - `WTF` wtfs per min: if a reader says 'wtf' more than twice in a minute, it's wrong
  - `WET` write everything twice: if a reader says "i think i've seen this before", it's wrong

## Sequence
> code order, top to bottom, marked with numbered comments (see example script above)

- `1. global constants` first, then types, so nothing below re-declares what the top settled
- `2. hoisted state` next, since a reader needs the mutable surface before the logic touches it
- `3. defined helpers` after that, each doing one thing and named for the thing it does
- `4. main logic & execution` last, so the file ends where the work actually happens

## Verify
- RUN `plugins/retardify/skills/code/code.sh <path>` after writing or editing logic
- FIX every ERROR, since each one breaks a rule this spec states outright
- STOP on a `secret` finding and ask the user before truncating it; the key needs rotating first
- JUSTIFY or fix every WARN; the sidecar tolerates them, the next reader may not
- ANSWER the checklist it prints, since those rules are the ones no script can judge
- APPEND the run to `audit_file` from the telemetry, in the shape below, when invoked deliberately
- SKIP that append when the run came from the posttooluse hook, which lints rather than audits
- RE-RUN the sidecar after fixing, so the findings you closed are proven closed

## Artifact Template
> the artifact this skill appends to; the sidecar grades what landed on its next run

```
# .construct/retardify/code/YYYY-MM-DD.md
one file per day, appended to by every deliberate run:

- the heading reads `## Code Audit #[next_audit]: [timestamp]`, both taken from the telemetry
- an audit captures one file at a moment in time, so it is never edited after the fact
- carry an unresolved finding forward by restating it, never by editing the older audit
- lines are hyphen bullets holding a single clause, capped at 100 characters
- scrub client names, tokens, and other sensitive detail before it lands in a commit

## Code Audit #1: YYYY-MM-DD HH:MM

### state
the counts as hyphen bullets: the file graded, its lines, errors, warnings

*example:*
> - src/utilities/net.ts graded at 214 lines, js checks on
> - 1 error and 6 warnings, so one rule the spec states outright is broken

### findings
one bullet per issue, leading with the label the sidecar printed

*example:*
> - **ternary** — net.ts:41 chains two ternaries, which an if-statement says plainer
> - **nesting** — 4 lines past the depth cap, worst at net.ts:68
> - **short_name** — 2 callbacks named `e`, which says nothing about what they hold

### resolutions
one checkbox per finding, in the same order, each carrying something a reader can run

*example:*
> - [ ] `/retardify:code src/utilities/net.ts` after splitting the ternary into an if
> - [ ] `/retardify:code src/utilities/net.ts` once the retry pyramid reads at depth 1
> - [ ] rename both callbacks, then `plugins/retardify/skills/code/code.sh src/utilities/net.ts`

### telemetry
the sidecar's whole output, fenced and unedited, so every claim above can be checked against it

*example:*
> ```text
> === code.sh sidecar ===
> file: src/utilities/net.ts
> lines: 214
> errors: 1
> warnings: 6
> ```

## Code Audit #2: repeat the above format for each deliberate run on the same day
never edit an earlier audit; a stale finding is signal about how long it went unresolved
```

## Help
> IF the invocation carries `--help` or `-h`, this section is the whole turn:

```text
SKILL: /plugin:name
DESCRIPTION: <the `description` frontmatter, verbatim>
POSTURE: <the readme index's keyword for this skill>
FLAGS:
- --flag: <what it changes, in the telemetry bullet's own words>
ARGUMENTS:
- <arg>: <what it names>
ARTIFACT: <the `metadata.artifact` path, or none>
OUTPUT: <what lands in the turn: an audit entry, a handover block, an inline report>
SPEC: <this doc's own path>
```

- every field prints, in this order; one with nothing to say prints `none`
- every value is COPIED from the source named beside it, never composed fresh
- ask what they are actually trying to do, and what they have already tried
- name the flag or the sibling skill that fits their answer, then STOP
- run no step, write no file, and never fall through to step 1

## Subagent Style
```!
awk 'NR>1 && /^---$/ {p=1; next} p' "${CLAUDE_PLUGIN_ROOT}/subagent-styles/operator.md"
```

---
name: quiz
model: fable
effort: max
license: MIT
compatibility: requires bash, git
description: turn a shipped feature into a study map and an ungraded 20-question quiz (saves quiz to .construct/)
argument-hint: "[--help] <feature>"
disable-model-invocation: true
metadata:
  kind: trigger
  artifact: .construct/retardify/quiz/
---
**an ungraded quiz on your own shipped code:** you still learn what the agent wrote
- a study map in build order, then 20 questions written against the code
- generation ships NO answers, and a second run grades what you ticked
- every miss names the transferable concept underneath it, not just the letter

# Instructions

## Telemetry
```!
"${CLAUDE_PLUGIN_ROOT}"/skills/quiz/quiz.sh $ARGUMENTS
echo "sidecar exit: $?"
```
- `help: requested` → the run was refused before it started; `## Help` below is the whole turn
- it already ran, so there is no command to issue
- fail (`sidecar exit` > 0) → abort and report the raw terminal error inside a markdown code block
- `state: graded` → this quiz is already scored; ASK whether to write a fresh one, then WAIT
- `state: ungraded` → the quiz is taken and waiting on a grade, so SKIP to step 3
- success (`sidecar exit` = 0) and `state: absent` → take `target` and continue to step 1

1. read the feature before writing a question about it
  - read every file the feature touches, and follow the imports rather than guessing at them
  - work out the order somebody should read them in to understand it from nothing
  - that order is ideal-build order, which is neither alphabetical nor the order you opened them

2. write `[target]` in the shape defined under `## the shape` below, then STOP
  - `Files`, `Model` and `Pattern` are the study half, and they carry no questions
  - `Quiz` is 20 questions, each with four options and NO indication of which is right
  - questions test the why, the tradeoff and the order of operations, never trivia recall
  - a question whose answer is visible in the study half above teaches nothing; ask past it
  - stamp `- generated:` and leave `- graded:` off entirely; the grade is a later run
  - show the saved quiz inline and STOP, so the user can take it

    NEVER write the answer, mark an option, or hint at one, in any form, for any reason
    a quiz whose answers ship with it measures reading comprehension and nothing else

3. grade the taken quiz, once the user has ticked their picks
  - read each `- [x]` pick, work out the right answer from the code, and mark it `- [x]` too
  - add one `> ✓` line per correct answer, saying in one clause why it is right
  - add one `> ✗ picked <X>, answer <Y>` line per miss, explaining the actual mechanism
  - add a `> 📚 study:` line under each miss, naming the transferable concept and where to read it
  - stamp `- graded:` with the score, then close with the blind-spot map across every miss

4. validate what landed, then show it and STOP
  ```bash
  plugins/retardify/skills/quiz/quiz.sh --check [target]
  ```
  - FIX every ERROR and re-run; a quiz that fails its own validator is not saved work
  - show the saved quiz inline, then STOP

    NEVER refactor the feature you were asked to quiz, and never offer to
    a quiz that quietly improves its subject is testing something that no longer exists

## the shape
> the spec this skill writes against; the validator below grades what landed

**the file:** `.construct/retardify/quiz/YYYY-MM-DD-<feature>.md`, kebab-case, one per sitting
- dated rather than replaced, since retaking a quiz later is how progress gets measured
- files are listed in ideal-build order, never alphabetical and never touched-order
- maximally concise, roadmap-style language — a map, not a textbook
- lines carry a single clause, capped at 100 characters, and never wrap
- scrub client names, tokens, and other sensitive detail before it lands in a commit

# QUIZ: Short Title
one line 'big idea' description of the topic/feature/concept the quiz covers

## Files
one line per file: what it is, why it's in this spot, one clause max

*example:*
> - [x] `types.ts` is the shape everything downstream returns; read this first, always
> - [x] `apis/source.ts` does raw fetch only, no formatting; the "one call, cache it" pattern
> - [x] `aggregate.ts` is where raw data becomes UI-ready strings; the fail-soft pattern lives here
> - [x] `Widget.tsx` is dumb consumer; if this file surprises you, the layer below did its job wrong

## Model
the one idea to walk away with, 1-3 lines, no more

*example:*
> raw source → per-source derivation → aggregate (format + cache + fail-soft) → dumb UI.
> every new stat repeats this exact chain — nothing skips a layer, nothing shares a fetch.

## Pattern
how to build the next similar thing, using this as the reference

*example:*
> 1. add the shape to `types.ts`
> 2. build one raw source under `apis/`, one job, no formatting
> 3. derive + format + cache in `aggregate.ts`
> 4. wire the dumb UI row last

## Quiz
20 questions, one answer each — graded against the code on a later run
- generated: YYYY-MM-DD HH:MM
- graded: YYYY-MM-DD HH:MM — score N/20 (missed QX)

**as generated:** four options, nothing marked, no verdict line

*example:*
> **Q1 — why is `exclusions.mjs` plain `.mjs` instead of `.ts`?**
> - [ ] A. `.mjs` loads faster than compiled `.ts` at runtime
> - [ ] B. build scripts run in plain node, and TS runtime files can import `.mjs` either way
> - [ ] C. the framework config requires filter modules to be `.mjs`
> - [ ] D. a `.ts` file would be caught by its own denylist

**as graded:** the pick and the answer are both marked, and a verdict line closes each question

*example:*
> **Q1 — why is `exclusions.mjs` plain `.mjs` instead of `.ts`?**
> - [ ] A. `.mjs` loads faster than compiled `.ts` at runtime
> - [x] B. build scripts run in plain node, and TS runtime files can import `.mjs` either way
> - [ ] C. the framework config requires filter modules to be `.mjs`
> - [ ] D. a `.ts` file would be caught by its own denylist
>
> ✓ B — the one format both plain-node build scripts and the TS runtime read without a compile

**a miss carries the mechanism and the concept behind it**

*example:*
> ✗ picked A, answer C — a 404 returns to the caller untouched; only 429/5xx enter the retry loop
> 📚 study: transient vs deterministic failure — 4xx means the request is wrong, retrying cannot fix

**the blind-spot map** closes a graded quiz, naming what the misses have in common

*example:*
> the single miss is not a feature gap; it is a general concept that happens to surface here.
> the frontier is the transferable ideas underneath the system, not the system itself.

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

## Output Style
```!
awk 'NR>1 && /^---$/ {p=1; next} p' "${CLAUDE_PLUGIN_ROOT}/output-styles/operator.md"
```

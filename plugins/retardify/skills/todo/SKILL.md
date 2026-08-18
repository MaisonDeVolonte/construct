---
name: todo
model: opus
effort: high
license: MIT
compatibility: requires bash, git
description: scan repo, docs, logs and threads for what to work on next, ranked urgent/important (saves to .construct/)
argument-hint: "[--help] [--test]"
disable-model-invocation: true
disallowed-tools: Edit
metadata:
  artifact: .construct/retardify/todo/
---

# Instructions

## Telemetry
```!
"${CLAUDE_PLUGIN_ROOT}"/skills/todo/todo.sh $ARGUMENTS
echo "sidecar exit: $?"
```
- `help: requested` → the run was refused before it started; `## Help` below is the whole turn
- it already ran, so there is no command to issue
- report-only; it never fails the run — capture its telemetry (broken references + code markers)
- `--- threads ---` is the session digest: one block per transcript, newest first
- `TODO_THREADS` sets how many sessions it digests (default 10)
- `TODO_THREAD_CHARS` sets the digest's character budget (default 12000)
- `threads_cut` above zero means the oldest threads fell outside the budget; say so in `sources`

1. reconcile docs against reality — run this block once per objective, one objective at a time:
  - **read:** the source of truth (the code, dirs, or config the doc describes)
  - **search:** where the doc makes claims about it
  - **reconcile:** does every claim still match reality?
  - **flag:** each drift as an opportunity (note the file and the mismatch)

  objectives (one at a time):
  - **README.md** — does it still describe the project, stack, and setup accurately?
  - **AGENTS.md** — do its prose rules still hold (naming, css, imports, mirroring, etc.)?
  - **plugins/\*/** — does each skill's doc still match its own sidecar's flags and behavior?

2. read the 5 most recent agent logs in `.construct/operator/logs/`, the shape `/operator:logs` defines
  - extract observations, pain points, unfinished tasks, recurring bugs, or architectural ideas

3. read the `--- threads ---` digest above, which is the raw session history the logs summarize
  - a log entry is written after a turn closes, so a thread that ended without one appears only here
  - each block carries a session id, its timestamp, its byte size and the operative's own prompts
  - `prompt>` is a short thread in full; `opened>` and `closed>` bracket a long one
  - read a `closed>` line as the last thing asked, so an unanswered ask there is unfinished work
  - open the transcript itself for any thread whose digest reads unresolved, and nothing more:
    - `~/.claude/projects/<cwd with every non-alphanumeric byte hyphenated>/<session id>.jsonl`
    - grep it, never read it whole; the files above run past 1MB each
  - a task the digest shows and no log or artifact records is a Q1 opportunity, since nothing tracks it

4. merge all four streams, dedupe, and evaluate against the urgent/important matrix:
  - **Q1 (urgent and important):** broken references, blockers, doc/code drift that misleads
  - **Q2 (urgent but not important):** code markers, minor configuration fixes, trivial tool warnings
  - **Q3 (not urgent but important):** refactoring, tech debt, architectural hygiene, core feature work
  - **Q4 (not urgent or important):** overly ambitious refactors, nice-to-haves, out-of-scope ideas

5. generate the final report:
  ```markdown
  # /retardify:todo report
  *synthesized from sidecar findings, doc reconciliation, the last 5 agent logs and N session threads (YYYY-MM-DD to YYYY-MM-DD)*

  ## observations
  - hyphen-delimited list of bullets

  ## opportunities
  **urgent and important:**
  - hyphen-delimited list of bullets

  **urgent but not important:**
  - hyphen-delimited list of bullets

  **not urgent but important:**
  - hyphen-delimited list of bullets

  **not urgent or important:**
  - hyphen-delimited list of bullets
  ```

6. THEN append the same report to the todo file, in the shape defined under `## the shape` below
  ```text
  - the sidecar reports the target but never creates it; take it from the telemetry header:
  - CREATE the file first if it does not exist, with `# <todo_file>` as its only line
    - `todo_file` is the path, `todo_time` is the heading timestamp
    - `todo_count` is how many reports the file already holds, so this one is #(todo_count + 1)
  - append a new `## Todo #N: YYYY-MM-DD HH:MM` section, never overwrite an earlier report
  - write the report as delivered to the user, minus the raw sidecar dump
  - an opportunity that recurs across dated files is a finding in itself; restate it, never edit the older report
  ```

## the shape
> the spec this skill writes against; the validator below grades what landed

# .construct/retardify/todo/YYYY-MM-DD.md
one file per day, appended to by `/retardify:todo` and nothing else:

- a report captures the opportunity surface at a moment in time, never edited after the fact
- `observations` are what the four streams found; `opportunities` are what to do about it
- an opportunity sorts onto the urgent/important matrix, and names the file it touches
- an opportunity that recurs across dated files is a finding; restate it, never edit the older one
- a Q1 entry that survives three reports has stopped being urgent in practice, so say so
- skip the raw sidecar dump; keep the read of it, not the printout
- lines hold a single clause, fact or action, capped at 100 characters
- scrub client names, tokens, and other sensitive detail before it lands in a commit

## Todo #1: YYYY-MM-DD HH:MM

### sources
which streams fed this report, and the log range read

*example:*
> sidecar: 3 broken refs, 6 markers | docs: README, AGENTS.md | logs: 2026-07-24 to 2026-07-29 | threads: 8 of 10, 0 cut

### observations
what the four streams actually surfaced:
- hyphen-delimited list of bullets

*example:*
> `review.sh` greps `content/**`, a path that no longer exists in this repo
> README documents a `.gitkeep` scaffold that `.gitignore` no longer preserves
> logs mention the same hook-testing gap on 3 separate days
> thread `9bf0f5a5` closed on an unanswered ask about `setup.sh --audit`, and no log records it

### opportunities
**urgent and important:**
- broken references, blockers, doc/code drift that misleads

**urgent but not important:**
- code markers, minor configuration fixes, trivial tool warnings

**not urgent but important:**
- refactoring, tech debt, architectural hygiene, core feature work

**not urgent or important:**
- overly ambitious refactors, nice-to-haves, out-of-scope ideas

### carried
opportunities restated from an earlier report, with how many reports they have survived

*example:*
> hook test coverage — carried 3 reports, still Q1 on paper, evidently not urgent in practice

## Todo #2: repeat the above format for each `/retardify:todo` run on the same day
never edit an earlier report; a recurring opportunity is signal about what keeps getting skipped

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

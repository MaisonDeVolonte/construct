---
name: plan
model: opus
effort: max
license: MIT
compatibility: requires bash, curl, git
description: turn work into a staged plan with per-stage readiness tables, then validate it (saves plan to .construct/)
argument-hint: "[--help] [--confirm] <text> [--test]"
disable-model-invocation: true
metadata:
  artifact: .construct/retardify/plan/
---

# Instructions

## Telemetry
```!
"${CLAUDE_PLUGIN_ROOT}"/skills/plan/plan.sh "$ARGUMENTS"
echo "sidecar exit: $?"
```
- `help: requested` → the run was refused before it started; `## Help` below is the whole turn
- it already ran, so there is no command to issue
- fail (`sidecar exit` > 0) → abort and report the raw terminal error inside a markdown code block
- `collision: yes` → STOP and name the file already holding that slug; never overwrite a plan
- `confirm: required` → the argument was a path; `## Confirm` below is the whole turn
- `spec: <path>` → read that file whole before step 1 and treat it as the brief
- `spec_kind: graph` → it carried a `GOAL:` line, so the goal and the filename came from it
- `spec_kind: brief` → any other file, so the goal was derived and the confirmation grades it
- success (`sidecar exit` = 0) → take `target` from the telemetry and continue to step 1

1. gather what the plan rests on before drafting a line of it
  - read the repo for the motivation, the obstacle, the constraint and the guardrails
  - with `spec: <path>`, read that file whole first; what it already answers is never re-asked
  - ASK the user for whatever the repo cannot answer, in one round, then WAIT for the answers
  - the round is lettered `a.`, `b.`, `c.`, in one fenced block, with no prose between the rows
  - verify any claim carrying a number before it lands, or leave the number out

2. release the user before writing a line, in one of these two forms and no other
  ```text
  QUESTIONS: a, b, c above are the whole round; answer them and you are free for the rest
  UNATTENDED: no questions; this runs alone for a few minutes and ends on the saved plan
  ```
  - it lands after the question block, or instead of one, and never mid-write
  - so the user knows whether to stay before the long part starts, rather than after it
  - past this line nothing else is asked; a gap becomes an `ALERT` row above the checklist
  - every question this step DID ask is a hole in the spec, recorded as a numbered note

3. write `[target]` in the shape defined under `## the shape` below
  - sections in order: context, goal, solution, risks, checklist, readiness, notes
  - stages are numbered `### <n>. <name>`, run in sequence, and each ships as its own pr
  - risks sort by blast radius and irreversibility, never by likelihood
  - readiness states feasibility only; a row proposing new work belongs in the checklist
  - every permission row is quoted exactly from a settings file, or labelled a proposal
  - notes are numbered so every `(see #x)` resolves, and are the only place verbosity belongs

4. validate what landed, then show it and STOP
  ```bash
  plugins/retardify/skills/plan/plan.sh --check [target]
  ```
  - FIX every ERROR and re-run; a plan that fails its own validator is not saved work
  - show the saved plan inline, then STOP

    NEVER start stage 1 in the same turn, and never offer to; the plan IS the deliverable
    it gets read, argued with and edited before anything is built against it

## the path argument
the argument is a goal in prose OR a path to any file, and the path form is the one `--plan` was
written for:

- `/retardify:plan .construct/retardify/graph/2026-08-06-operation-snap-mvp.md` is the whole invocation
- a path is recognised by resolving to a file, never by its extension or its directory
- a `GOAL:` line makes it a `/retardify:graph` spec, and that line becomes the goal verbatim
- any other file is a brief, and its first `# ` heading becomes the goal instead
- a brief with no heading falls back to its filename, stripped of the date and the extension
- the plan inherits the source's basename when that reads `YYYY-MM-DD-operation-<title>.md` already
- any other source names the plan from its own filename, since an inherited one fails `--check`
- a path that resolves to nothing is refused, since a typo would otherwise plan the wrong work
- every path stops on `confirm: required`, since the goal and the filename were derived not typed
- the spec's `CONTEXT:` answers step 1, so the questions there are asked only about what it omits
- the spec's `DONE WHEN:` is the readiness table's source, and `FAN OUT:` suggests the stages
- a path run still writes a normal plan and still passes `--check`; nothing about the shape changes

## the shape
> the spec this skill writes against; the validator below grades what landed

**the file:** `.construct/retardify/plan/YYYY-MM-DD-operation-<title>.md`, one per plan
- written before complex or architectural work, never after it
- sections run in this order: context, goal, solution, risks, checklist, readiness, notes
- a completed plan closes with a summary in `notes`; a `## Summary` section breaks that order
- an unticked box is live work, or an abandoned `~~SKIPPED: <why>~~` that says so outright
- a question the plan could not close rides in an `ALERT` fence directly above `## Checklist`
- it sits there because an open question can invalidate every stage under it, so it is read first
- rows are numbered 1..n with no gap, and the block is omitted whole when nothing is open
- scrub client names, tokens, and other sensitive detail before it lands in a commit

**the style:** maximally clear, concise, action-oriented language
- write for humans, not machines: plain english over jargon, facts over metaphor
- lead with the core idea, so plan steps are easy to scan and understand
- lines carry a single clause, capped at 100 characters, and never wrap
- body sections state conclusions only; the reasoning lives in numbered notes
- order every list deliberately; if the order is not obvious, say why in a note
- a claim with a number in it gets verified before it lands, or it does not land

# AGENT PLAN: Operation [non-serious title]
one plain-english line: what this plan does

## Context
why the work exists, in briefing order: motivation, obstacle, constraint, sequence, guardrails
- one clause per line, each a fact stated the way a general states it before a mission
- name the pain first, then what blocks it, then the rule that shapes the fix (see #1)
- supporting detail moves to a note, never inline
- no jargon a newcomer would have to look up, and no metaphor where a fact will do

## Goal
one line stating the finished state
```
a tree or diagram that makes the destination concrete
  describe what things ARE, never what changes about them
  no change markers, no stage numbers - both rot as the work lands
  sort entries to match the real thing, so it can be diffed by eye
```

## Solution
the strategy: one decision per line, never a restatement of the checklist
- each line is a choice that was made, with the reasoning in a note (see #2)
- if a line could be pasted into the checklist unchanged, it belongs there instead

## Risks
sorted by blast radius and irreversibility, never by likelihood
- `destroys production` first, then anything that destroys work (see #3)
- `ships silently` next: wrong behavior that nobody notices
- `costs an hour` last: a red check is an inconvenience, not a risk
- label each with a noun naming the actual risk, never a category like `edge case`

```
ALERT: Please answer the following questions to finalize this plan file.
1. every question the plan could not answer, one per line
2. asked as a question, never as a statement of the gap
3. omitted entirely when nothing is open
```

## Checklist

### 1. Stage name
- [ ] short directives, verb first, one line each (see #4)
- [ ] point at a note for context rather than explaining inline
- [ ] no prose, no rationale, no sub-bullets that are really notes
- [ ] HUMAN: tasks blocking fully agentic work are labelled clearly
- [ ] ~~SKIPPED: abandoned items are wrapped in tildes, never deleted~~

### 2. Next stage
- [ ] stages run in sequence and each ships as its own pr
- [ ] a stage that touches no files still earns a stage, if it gates the next one

### Deferred Work
closes the checklist as a wishlist, never a section of its own
- [ ] a wishlist of findings
- [ ] that could be added to a future plan (see #5)
  - [ ] derived from the work in this plan

## Readiness
states feasibility only; a row proposing new work belongs in the checklist instead

### Blockers
unrelated tasks to clear before starting this plan, if any, found in other open plans:

| task | blocks | where |
|---|---|---|
| 1. task name | what it's blocking | where to find it |
| 2. task name | what it's blocking | where to find it |

### Agents
how each stage's checklist items are split by who can run them:
- every item in a stage counts as exactly one of the three, and the three sum to the stage
- `agentic` matches an allow rule with no deny
- `human-only` matches a deny, or needs judgment, credentials, or a decision
- `gated` matches neither, so it prompts
- every `human-only` item carries the `HUMAN:` label, so the column and the labels agree
- a skipped item keeps its label and its count, since the three still sum to the stage
- a closed plan is exempt, since an abandoned item stays unticked and is not work

| stage | agentic | human-only | gated | note # |
|---|---|---|---|---|
| 1. stage name | 4 | 1 | — | see #3 |
| 2. stage name | — | — | 2 | see #5 |

### Permissions
suggested rules to set in order for agents to work reliably:
- quote every rule exactly from a settings file, or label it a proposal
- a rule holding a pipe escapes it as `\|`, since an unescaped one splits the table
- deny beats allow, so a denied path is narrowed at the deny rule, never granted an allow
- never propose a managed rule, since that is a sudo edit and a policy decision
- `layer` names which system enforces the row, since each takes a different rule shape:
  - `permissions` = `Tool(pattern)`, and covers every tool
  - `sandbox filesystem` = a bare path, and covers bash writes and reads only
  - `sandbox domain` = a bare host, and covers bash network egress only
- a bash step that writes outside the working directory needs a sandbox row, even when a
  permission rule already allows the command; the two layers are enforced separately
- `scope` is where the rule lands: repo-specific goes to project, machine detail to user

| rule | layer | scope | suggestion |
|---|---|---|---|
| 1. `Bash(abc *)` | permissions | project | add to allow |
| 2. `Edit(**/xyz/**)` | permissions | project | narrow deny |
| 3. `~/Library/Caches/abc` | sandbox filesystem | user | add to allowWrite |
| 4. `registry.abc.org` | sandbox domain | project | add to allowedDomains |

#### Explanations
1. `abc` prompts in every stage today, and project scope carries the grant to a fresh clone
2. `xyz` already matches a deny, and deny beats allow, so an added allow would never take effect
3. a cache path is machine detail, so it goes to user; the sandbox blocks it even with row 1 allowed
4. an unlisted host prompts on first contact, and the registry is this repo's own dependency

## Notes
1. numbered, so `(see #1)` resolves; renumbering means renumbering every reference too
2. this is where verbosity belongs: evidence, commands, measurements, exact file paths
3. record what was ruled out and why, so a future reader does not relitigate it
4. keep each note self-contained, since readers jump here from one line and jump straight back
5. a note nothing points at is either dead weight or a missing `(see #x)` somewhere

## Confirm
> IF the telemetry reads `confirm: required`, this section is the whole turn:

```text
SOURCE: <the `spec` path, then its `spec_kind`>
GOAL: <the `goal` line, verbatim>
TARGET: <the `target` path>
```

- show what was derived BEFORE asking, since the goal and the filename were never typed
- then ask for a go in one line, and STOP; a wrong source spends the whole write before it reads
- run no step, write no file, and never fall through to step 1
- on a go, continue from step 1 with this telemetry, since the sidecar wrote nothing to redo
- on a corrected goal, run the sidecar again with that goal as prose, so it names the file
- `--confirm` on the invocation skips this section for anyone who already knows the answer
- an earlier confirmation never covers a later run

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

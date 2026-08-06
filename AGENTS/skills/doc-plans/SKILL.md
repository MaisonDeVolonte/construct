---
name: doc-plans
description: Shape of a plan in docs/plans/: context, goal, solution, risks, checklist, readiness, notes.
metadata:
  kind: spec
---
**the file:** `docs/plans/YYYY-MM-DD-operation-<title>.md`, tracked in git, one per plan
- written before complex or architectural work, never after it
- sections run in this order: context, goal, solution, risks, checklist, readiness, notes
- a completed plan closes with a summary in `notes`; a `## Summary` section breaks that order
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

## Checklist

### 1. Stage name
- [ ] short directives, verb first, one line each (see #4)
- [ ] point at a note for context rather than explaining inline
- [ ] no prose, no rationale, no sub-bullets that are really notes

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

```text
VERIFY - not part of the artifact
- RUN `AGENTS/skills/doc-plans/doc-plans.sh` once the plan is written; pass a path to scope the run
- FIX every ERROR, since each one breaks a rule this spec states outright
- STOP on a `secret` finding and ask the user before truncating it; the key needs rotating first
- JUSTIFY or fix every WARN; the sidecar tolerates them, the next reader may not
- ANSWER the checklist it prints, since those rules are the ones no script can judge
```

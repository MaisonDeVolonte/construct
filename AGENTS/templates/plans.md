```javascript
/**
 * ==============================
 * @file plans.md - plan template
 * ==============================
 * @description
 * - one file per plan, `docs/plans/`, named `YYYY-MM-DD-operation-<title>.md`
 * - tracked in git
 * - scrub client names, tokens, and other sensitive detail before it lands in a commit
 * - written before complex or architectural work
 * - sections run in this order: context, goal, solution, risks, checklist, future work, notes
 * - plans are written in maximally clear, concise, action-oriented language
 * - write for humans, not machines: plain english over jargon, facts over metaphor
 * - `lead with the core idea` so plan steps are easy to scan and understand
 * - `lines` carry a single clause, capped at 100 characters, and never wrap
 * - `body` sections state conclusions only; the reasoning lives in numbered notes
 * - `notes` are numbered so every `(see #x)` resolves, and are the only place verbosity belongs
 * - prefer a short line plus `(see #x)` over a long line that explains itself
 * - `order` every list deliberately; if the order is not obvious, say why in a note
 * - a claim with a number in it gets verified before it lands, or it does not land
 * - `AGENTS/templates/plans.sh` validates a plan against every rule above a script can judge
 * @see AGENTS.md, AGENTS/templates/plans.sh, AGENTS/templates/logs.md, docs/plans/
 */
```

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
```text
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

## Future Work
- [ ] a wishlist
  - [ ] of all sorts of findings
  - [ ] and side quests
- [ ] that could be added (see #5)
- [ ] to a future plan

## Notes
1. numbered, so `(see #1)` resolves; renumbering means renumbering every reference too
2. this is where verbosity belongs: evidence, commands, measurements, exact file paths
3. record what was ruled out and why, so a future reader does not relitigate it
4. keep each note self-contained, since readers jump here from one line and jump straight back
5. a note nothing points at is either dead weight or a missing `(see #x)` somewhere

```text
VERIFY - not part of the artifact
- RUN `AGENTS/templates/plans.sh` once the plan is written; pass a path to scope the run
- FIX every ERROR, since each one breaks a rule stated in the header above
- STOP on a `secret` finding and ask the user before truncating it; the key needs rotating first
- JUSTIFY or fix every WARN; the sidecar tolerates them, the next reader may not
- ANSWER the checklist it prints, since those rules are the ones no script can judge
```

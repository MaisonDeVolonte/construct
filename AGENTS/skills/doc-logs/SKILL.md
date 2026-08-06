---
name: doc-logs
description: Shape of a daily agent log in docs/logs/: threads, notes, and prompts.
metadata:
  kind: spec
---
```javascript
/**
 * ============================
 * @file SKILL.md - log template
 * ============================
 * @description
 * - one log file per day, holding both the work and the prompts that drove it
 * - gitignored in this repo; host projects decide for themselves whether to track it
 * - scrub client names, tokens, and other sensitive detail before it lands in a commit
 * - `logs` are written in MAXIMALLY clear, concise, casual language, skipping trivial details
 * - `threads` group work by task/topic, limited to 50 lines of prose, prompts excluded
 * - `sections` lead with the main idea, followed by supporting ideas
 * - `lines` should contain a single clause/fact/action, limited to 100 characters
 * - `notes` are appended after taskcomplete or every 30 minutes, limited to 5 bullets
 * - manual triggers: `@logthread` adds a thread, `@lognote` a note, `@logsynth` a synthesis
 * - `prompts` are appended to the thread they drove, rewritten short, always timestamped
 * - a prompt that starts a new thread belongs to the thread it created, not the one before
 * - `synthesize` means two different things, never conflate them:
 *   - for notes, `incorporate & delete` them into the thread's prose
 *   - for prompts, `prune & rewrite` them in place; they stay a list, never becoming prose
 * - prune a prompt once it is trivial, redundant, or superseded by the one after it
 * - keep the prompt that changed direction, dropped a constraint, or corrected a wrong assumption
 * - minimize comma chains, em dashes, **bold**, `ticks`, and superfluous formatting
 * - focus on outcomes, not the conversation (no play-by-plays)
 * - err on the side of brevity, not completeness
 * - ultimately, logs should only capture the most meaningful signals, ignoring noise
 * - `AGENTS/skills/doc-logs/doc-logs.sh` validates a log against every rule above a script can judge
 * @see AGENTS.md, AGENTS/skills/doc-logs/doc-logs.sh, docs/logs/
 */
```

# docs/logs/YYYY-MM-DD.md

## Thread #1: project - short description

### context
outline repo state, inherited problems, and current goals

*example:*
> after discovering that Will is actually, literally, retarded, i proposed a strict logging protocol

### changes
list any work or prs you delivered:
- in a bulleted list 
- of maximally concise descriptions
- and/or 
- PR #88: a numbered list of prs 

*example:*
> draft memory log protocol in PR #14:
> - added root instructions
> - established folder schema
> - PR #14 `new(agents): implement agent memory logging protocol`

### insights
brutally honest retrospective:
- what went right
- what went wrong
- lessons learned
- surprises encountered

*example:*
> task went fine despite my human being utterly useless
> reviewing logs before every task was annoying, but actually useful ngl
> hooks are more reliable than prompts
> SessionEnd hook apparently can't be used to write a log lol

### advice
generate a list of potential tasks to work on next
- [ ] group tasks into atomicized buckets
  - [ ] in a sequential, checklist style
  - [ ] written sequentially 
  - [ ] with clear, actionable steps

*example:*
> - [ ] test agent memory logs:
>   - [ ] test generation: start thread, run `@git-audit`, close thread, verify log
>   - [ ] test review: start thread, prompt "continue where we left off", verify context pickup

#### NOTE: YYYY-MM-DD HH:MM
output a subject: followed by a description
- and a bulleted list
- of thoughts
- since the last note

*example:*
> #### NOTE: 2026-07-16 19:25
> unfucked the repo while user was AFK:
> - renamed file
> - hardened logic
> - updated docs

#### PROMPTS
what the user actually asked, in the thread it drove
- HH:MM one rewritten prompt per line, never the original wording
- keep the ask, drop the throat-clearing, hedging, and acknowledgments
- skip one-word replies, confirmations, and "wdyt" entirely
- this block stays a list; notes get absorbed into prose above, prompts never do

*example:*
> #### PROMPTS
> - 11:40 logs and prompts are only individually useful, the rest have value to others
> - 11:45 merge prompts into the log file, at the bottom of the thread they belong to
> - 11:52 add a synthesis rule so they stay pruned

## Thread #2: Repeat the above format for each meaningful unit of work
synthesize pending notes when creating a new thread, and prune that thread's prompts

```text
VERIFY - not part of the artifact
- RUN `AGENTS/skills/doc-logs/doc-logs.sh` after closing a thread, adding a note, or synthesizing
- FIX every ERROR, since each one breaks a rule stated in the header above
- STOP on a `secret` finding and ask the user before truncating it; the key needs rotating first
- JUSTIFY or fix every WARN; the sidecar tolerates them, the next reader may not
- ANSWER the checklist it prints, since those rules are the ones no script can judge
```

```javascript
/**
 * ============================
 * @file logs.md - log template
 * ============================
 * @description
 * - tracked in git, one log file per day
 * - scrub client names, tokens, and other sensitive detail before it lands in a commit
 * - `logs` are written in MAXIMALLY clear, concise, casual language, skipping trivial details
 * - `threads` group work by task/topic, limited to 50 lines
 * - `sections` lead with the main idea, followed by supporting ideas
 * - `lines` should contain a single clause/fact/action, limited to 100 characters
 * - `notes` are appended after taskcomplete or every 15 minutes, limited to 5 bullets
 * - `synthesize` means to `incorporate & delete` notes into corresponding threads
 * - minimize comma chains, em dashes, **bold**, `ticks`, and superfluous formatting
 * - focus on outcomes, not the conversation (no play-by-plays)
 * - err on the side of brevity, not completeness
 * - ultimately, logs should only capture the most meaningful signals, ignoring noise
 * @see AGENTS.md, docs/logs/
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
>   - [ ] test generation: start thread, run `@gitaudit`, close thread, verify log
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

## Thread #2: Repeat the above format for each meaningful unit of work
synthesize pending notes when creating a new thread

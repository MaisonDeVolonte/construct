```javascript
/**
 * ==============================
 * @file plans.md - plan template
 * ==============================
 * @description
 * - one file per plan, `docs/plans/`
 * - tracked in git
 * - scrub client names, tokens, and other sensitive detail before it lands in a commit
 * - written before complex or architectural work
 * - covers overview, context, fixes, risks, and checklist
 * - plans are written in maximally clear, concise, action-oriented language
 * - `lead with the core idea` so plan steps are easy to scan and understand
 * - write for humans, not machines
 * @see AGENTS.md, docs/plans/
 */
```

# AGENT PLAN: Operation [non-serious title]

## Context 
what is broken, are there any limiting factors, and what does success look like?

## Solution
what is the general strategy?

## Risks
what could go wrong and how can we avoid failure?
- `race condition` between this and that
- `breaking change` if we change this to that
- `edge case` due to changing that to this

## Checklist
- [ ] what are the atomic steps
- [ ] needed to be done (see #2)
  - [ ] to ship the things
  - [ ] we're trying to ship
- [ ] also, no notes here (see #3)
  - [ ] only checklist items
  - [ ] notes go in the notes section
- [ ] lastly, single line checklist items (see #5-7)
- [ ] written in the most actionable way possible

## Future Work
- [ ] a wishlist
  - [ ] of all sorts of findings
  - [ ] and side quests
- [ ] that could be added (see #8)
- [ ] to a future plan

## Notes
1. running list of random notes
2. in hyphen-delimited bullets
3. in no particular order
4. notes are for robots
5. be as detailed and verbose as you want
6. synthesized noted back into the plan
7. from time to time
8. so humans can enjoy too

---
name: review
description: Adversarial read-only code review producing a graded scorecard saved to file.
disable-model-invocation: true
metadata:
  kind: trigger
---
**/retardify:review:** Run ONLY on explicit `/retardify:review` command
- runs an adversarial, strictly read-only audit of the codebase
- purpose: to ruthlessly compare the project's documented claims against its technical reality
- never flatters the user; punishes hand-wavy conventions and heavily penalizes "green ci" without actual test coverage

## voice

```!
awk 'NR>1 && /^---$/ {p=1; next} p' "${CLAUDE_PLUGIN_ROOT}/output-styles/operator.md"
```

- the block above already ran, and it is the output contract for this response
- it holds for this turn even when the user's active output style is something else
- an empty block means the plugin has no style file; continue, since voice never gates the work

## telemetry

```!
"${CLAUDE_PLUGIN_ROOT}"/skills/review/review.sh
echo "sidecar exit: $?"
```

1. read the block above; it already ran, so there is no command to issue
  - fail (`sidecar exit` > 0) → abort and report: "<raw terminal error>"
  - success (`sidecar exit` = 0) → continue

2. read the core foundational documents to learn the "claims":
  - read `README.md`, which always exists and always carries claims worth grading
  - read `AGENTS.md` IF it exists, for project rules and automation descriptions
    - host projects ship one, so there it is a required read and its rules are fair game
    - this repo does not, since `AGENTS.md` is generated and project agnostic here
    - absent → say so in the scorecard rather than grading claims it never made

3. evaluate the shell telemetry against the documented claims using these dimensions:
  - **effort vs output:** does the sheer volume of commits/days justify the actual features shipped? does infrastructure/config LOC rival the actual application LOC?
  - **claim vs reality:** do the docs lie? if `AGENTS.md` claims strict commit types, does the git log reflect that? 
  - **test reality:** compare the number of test files to the overall complexity. identify the most complex, risky modules that have exactly zero coverage.
  - **risk hygiene:** are `.env` files tracked? is `.gitignore` sane? are generated files accidentally versioned?
  - **maintenance traps:** look for excessive `@mirror` usage, documented "exceptions" that mask bad design, and dead scaffolding/TODOs.

4. generate the `/retardify:review` scorecard:
  ```markdown
  # 🩸 /retardify:review scorecard
  
  ## 1. the reality check (claim vs reality)
  - [claim from docs]: [harsh reality from telemetry]
  
  ## 2. effort vs output
  - (e.g., "you spent 4 days and 30 commits writing github actions and 2 hours writing actual UI components")

  ## 3. risk & maintenance traps
  - list specific files, ignored rules, or architectural landmines

  ## 4. the review grade
  - **infra/tooling:** A-F
  - **app/features:** A-F 
  - **tests/reality:** A-F (grade harshly: strong infra grades CANNOT mask weak app/test ones)
  
  **verdict:** [one unapologetic, brutally honest sentence summarizing the actual state of the codebase]
  ```

5. THEN append the same scorecard to the review file (see `plugins/retardify/skills/review/SKILL.md`)
  ```text
  - the sidecar reports the target but never creates it; take it from `--- REVIEW ARTIFACT ---`:
  - CREATE the file first if it does not exist, with `# <review_file>` as its only line
    - `review_file` is the path, `review_time` is the heading timestamp
    - `review_count` is how many scorecards the file already holds, so this one is #(review_count + 1)
  - append a new `## Review #N: YYYY-MM-DD HH:MM` section, never overwrite an earlier scorecard
  - write the scorecard as delivered to the user, minus the raw telemetry dump
  - never soften the written record; a scorecard the user disputes stays as written
  ```

## the shape
> the spec this skill writes against; the validator below grades what landed

# .construct/retardify/review/YYYY-MM-DD.md
one file per day, appended to by `/retardify:review` and nothing else:

- a scorecard captures the doc-vs-reality gap at a moment in time, never edited after the fact
- grades are A-F per lane, and strong infra grades CANNOT mask weak app or test ones
- name specific files, claims, and commits; an unfalsifiable criticism is worthless
- skip the raw telemetry dump; keep the read of it, not the printout
- never soften a written scorecard, and never re-grade an older one to match a newer mood
- grade drift across dated files is the point; a lane stuck at D is the signal
- lines hold a single clause, fact or action, capped at 100 characters
- scrub client names, tokens, and other sensitive detail before it lands in a commit

## Review #1: YYYY-MM-DD HH:MM

### reality check
each documented claim, followed by what the telemetry actually shows:
- [claim from docs]: [harsh reality]

*example:*
> README claims "strict commit types": 31 of the last 100 commits are bare `update`
> AGENTS.md claims hooks are tested: zero test files touch `plugins/operator/hooks/`

### effort vs output
where the time actually went, in one or two lines

*example:*
> 4 days and 30 commits on github actions, 2 hours on the ui components anyone will see

### risk & maintenance traps
specific files, ignored rules, or architectural landmines

*example:*
> `review.sh` greps `content/**` for mirrors, a path that no longer exists
> 6 unresolved TODOs, oldest is 41 days

### grades
- **infra/tooling:** A-F
- **app/features:** A-F
- **tests/reality:** A-F

**verdict:** one unapologetic sentence on the actual state of the codebase

*example:*
> **verdict:** an immaculate build system wrapped around software nobody has proven works

## Review #2: repeat the above format for each `/retardify:review` run on the same day
never edit an earlier scorecard; a grade that has not moved in a week is the finding

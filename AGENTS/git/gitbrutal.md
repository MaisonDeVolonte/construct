```javascript
/**
 * =============================================================
 * @file gitbrutal.md - adversarial doc-vs-reality audit trigger
 * =============================================================
 * @description
 * - ran only on explicit `@gitbrutal` command; read-only, never mutates tracked files
 * - runs `AGENTS/git/gitbrutal.sh`, then reads `README.md`/`AGENTS.md` to learn the
 *   project's documented claims
 * - scores effort-vs-output, claim-vs-reality, test coverage, and risk hygiene against
 *   the shell telemetry
 * - outputs a harsh A-F scorecard with a one-sentence verdict; never flatters the user
 * - appends that scorecard to `docs/brutal/YYYY-MM-DD.md`, one file per day, many per file
 * @see AGENTS.md, AGENTS/templates/git.md, AGENTS/git/gitbrutal.sh, README.md, AGENTS/templates/brutal.md, docs/brutal/
 */
```

**@gitbrutal:** Run ONLY on explicit `@gitbrutal` command
- runs an adversarial, strictly read-only audit of the codebase
- purpose: to ruthlessly compare the project's documented claims against its technical reality
- never flatters the user; punishes hand-wavy conventions and heavily penalizes "green ci" without actual test coverage

1. run the native shell command exactly as specified:
  ```bash
  AGENTS/git/gitbrutal.sh
  ```
  - fail (exit code > 0) → abort and report: "<raw terminal error>"
  - success (exit code = 0) → continue

2. read the core foundational documents to learn the "claims":
  - read `README.md`
  - read `AGENTS.md` (specifically project rules and automation descriptions)

3. evaluate the shell telemetry against the documented claims using these dimensions:
  - **effort vs output:** does the sheer volume of commits/days justify the actual features shipped? does infrastructure/config LOC rival the actual application LOC?
  - **claim vs reality:** do the docs lie? if `AGENTS.md` claims strict commit types, does the git log reflect that? 
  - **test reality:** compare the number of test files to the overall complexity. identify the most complex, risky modules that have exactly zero coverage.
  - **risk hygiene:** are `.env` files tracked? is `.gitignore` sane? are generated files accidentally versioned?
  - **maintenance traps:** look for excessive `@mirror` usage, documented "exceptions" that mask bad design, and dead scaffolding/TODOs.

4. generate the `@gitbrutal` scorecard:
  ```markdown
  # 🩸 @gitbrutal scorecard
  
  ## 1. the reality check (claim vs reality)
  - [claim from docs]: [harsh reality from telemetry]
  
  ## 2. effort vs output
  - (e.g., "you spent 4 days and 30 commits writing github actions and 2 hours writing actual UI components")

  ## 3. risk & maintenance traps
  - list specific files, ignored rules, or architectural landmines

  ## 4. the brutal grade
  - **infra/tooling:** A-F
  - **app/features:** A-F 
  - **tests/reality:** A-F (grade harshly: strong infra grades CANNOT mask weak app/test ones)
  
  **verdict:** [one unapologetic, brutally honest sentence summarizing the actual state of the codebase]
  ```

5. THEN append the same scorecard to the brutal file (see `AGENTS/templates/brutal.md`)
  ```text
  - the sidecar reports the target but never creates it; take it from `--- BRUTAL ARCHIVE ---`:
  - CREATE the file first if it does not exist, with `# <brutal_file>` as its only line
    - `brutal_file` is the path, `brutal_time` is the heading timestamp
    - `brutal_count` is how many scorecards the file already holds, so this one is #(brutal_count + 1)
  - append a new `## Brutal #N: YYYY-MM-DD HH:MM` section, never overwrite an earlier scorecard
  - write the scorecard as delivered to the user, minus the raw telemetry dump
  - never soften the written record; a scorecard the user disputes stays as written
  ```

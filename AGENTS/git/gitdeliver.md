```javascript
/**
 * ===================================================
 * @file gitdeliver.md - gated atomic delivery trigger
 * ===================================================
 * @description
 * - ran only on explicit `@gitdeliver` command
 * - floats uncommitted changes onto trunk, then drains them one atomic `type(scope)`
 *   bucket at a time: branch → commit → push → pr → auto-merge on green → back to trunk
 * - `--first` flag stops after the first pr; re-runnable, `git status` drives the loop
 * - gated: drafts each pr command and waits for user confirmation before executing
 * @see AGENTS.md, AGENTS/templates/git.md, AGENTS/git/gitdeliver.sh
 */
```

**@gitdeliver:** Run ONLY on explicit `@gitdeliver` command
- floats uncommitted changes onto the trunk, then drains them one atomic bucket at a time
- each atomic bucket: branch → commit → push → PR → auto-merge on green, then back to the trunk for the next
- leaves you on the trunk, not a feature branch — the trunk is your working surface
- every change is either uncommitted on the trunk or committed on a pushed branch
- re-run anytime to resume; git status drives the loop, so it picks up whatever's left
- recover a failed `git switch -c` with `git switch "$DEFAULT_BRANCH"`, then `git branch -D "$ATOMIC_BRANCH"` (add `git push origin --delete "$ATOMIC_BRANCH"` if pushed)

**FLAGS:**
- `--first`: stops the process immediately after the FIRST pull request

1. run the native shell command exactly as specified
  ```bash
  AGENTS/git/gitdeliver.sh
  ```
  - fail (exit code > 0) → abort and report: "<raw terminal error>"
  - success (exit code = 0) → capture $DEFAULT_BRANCH from output

2. `git status -s` and `git diff`
- analyze changes and group into self-contained atomic `type(scope)` buckets
- interdependent files needed to pass CI should be grouped together
- tests are grouped with code they validate, matched via imports, routes, selectors, etc
- types (derived from the following, in order of precedence):
  - `new` → first-time features, functions
  - `improve` → existing features, functions
  - `fix` → defects, bugs, broken code
  - `update` → content, text, properties, comments, rename, remove
  - `debug` → logs, profiling scripts, temp instrumentation
  - exceptions:
    - `test` → test changes independent of other changes (no in-tree subject)
- scopes (derived from the following, in order of precedence): 
  - single file: file's `FullName.ext`
  - multiple files: parent folder's name
  - multiple folders: most logical domain name
  - multiple domains: most dominant domain name
  - multiple unrelated domains: `misc`
  - exceptions: 
    - `content` → any changes in `/content/` 

3. prepare atomic buckets for delivery
- sort the atomic buckets by dependency
- prioritize foundational changes
- choose the first atomic bucket
- populate the following variables:
```
$ATOMIC_FILES # space-delimited list of files to commit
$ATOMIC_TYPE # new, improve, fix, update, test, debug
$ATOMIC_SCOPE # FullName.ext, folder, domain, misc, content
$ATOMIC_TITLE # very short plain english title
$ATOMIC_TITLE_SLUG # very-short-plain-english-title
$ATOMIC_BRANCH # atomic-type/atomic-scope/atomic-title-slug
$ATOMIC_DESCRIPTION # multiline string of hyphen-delimited bullets
$ATOMIC_COMMIT # $ATOMIC_TYPE($ATOMIC_SCOPE): $ATOMIC_TITLE
```

4. present the following draft command and wait for confirmation:
```bash
git switch -c "$ATOMIC_BRANCH" "$DEFAULT_BRANCH"
git add $ATOMIC_FILES
git commit -m "$ATOMIC_COMMIT" -m "$ATOMIC_DESCRIPTION"
git push -u origin "$ATOMIC_BRANCH"
gh pr create --base "$DEFAULT_BRANCH" --fill
gh pr merge --auto --rebase
git switch "$DEFAULT_BRANCH"
```
- ask: "continue or make edits? (continue/edit)"
  - continue: execute the draft pr commands
  - edit: execute the exact user confirmed commands

5. check conditions before continuing:
- IF `--first` → STOP here and report completion
- ELSE repeat from step 2 until workspace is clean

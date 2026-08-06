---
name: git-deliver
description: Bucket uncommitted work into atomic PRs, gate the plan, then hand over every block.
argument-hint: [--first]
disallowed-tools: Write Edit
disable-model-invocation: true
metadata:
  kind: trigger
---
**@git-deliver:** Run ONLY on explicit `@git-deliver` command
- floats uncommitted changes onto the trunk, then drains them in atomic buckets
- each atomic bucket: branch → commit → push → PR → auto-merge on green, then back to the trunk
- the reasoning is the automation: bucketing, ordering, and message drafting are what it does for you
- never runs a bucket; every one is handed over as a block you paste into your own terminal
- leaves you on the trunk, not a feature branch — the trunk is your working surface
- every change is either uncommitted on the trunk or committed on a pushed branch
- re-run anytime to resume; git status drives the loop, so it picks up whatever's left
- recover a failed `git switch -c` with `git switch "$DEFAULT_BRANCH"`, then `git branch -D "$ATOMIC_BRANCH"` (add `git push origin --delete "$ATOMIC_BRANCH"` if pushed)

**FLAGS:**
- `--first`: plans every bucket as normal, but emits only the FIRST block

## telemetry

```!
"${CLAUDE_PLUGIN_ROOT}"/skills/git-deliver/git-deliver.sh
echo "sidecar exit: $?"
```

1. read the block above; it already ran, so there is no command to issue
  - fail (`sidecar exit` > 0) → abort and report: "<raw terminal error>"
  - success (`sidecar exit` = 0) → capture `default branch` from the telemetry
  - IF the handover block names any prep command, hand it over and WAIT before step 2
    - the preflight measures only, so the tree is still wherever the user left it
    - bucketing against an unsynced trunk drafts commits the user then has to redo
  - IF `touches .claude/settings.json` reads `yes`, say so now: no sandboxed command can write
    that path, so the pull after the merge needs the retry hatch

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

3. plan EVERY bucket, then STOP and gate on the plan
- sort the buckets by dependency and prioritize foundational changes
- populate these per bucket, for all of them, before emitting anything:
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
- emit the plan as a table, one row per bucket, and nothing runnable yet
  ```text
  | # | commit | files | depends on |
  |---|--------|-------|------------|
  | 1 | type(scope): title | n files | — |
  | 2 | type(scope): title | n files | 1 |
  ```
- name what each bucket delivers, and what it deliberately leaves to a later one
- mark any two buckets INDEPENDENT when their files are disjoint and neither references the other
- say plainly why a bucket cannot be split further when it looks large; a security-shaped
  grouping (a permission and the guard that bounds it) is atomic even at six files
- ask: "does this bucketing look right? say go and I'll emit every block"
- STOP here and WAIT; the plan is the gate, and a wrong bucket costs nothing to fix at this point

4. verify every bucket before emitting a single block, since a red PR costs a round trip
- resolve every reference a bucket breaks against `git show HEAD:<file>`, NEVER the working copy
- a path the working tree already fixed still reads broken to CI until its bucket lands
- run the validators each bucket touches, plus the two checks CI runs: `shellcheck -x` and `bash -n`
- CI does not gate references, so a bucket that breaks one still goes green — the read above is the check
- bucket 1 verifies against today's HEAD; every later bucket verifies against a trunk that does not
  exist yet, so say which buckets carry that weaker guarantee rather than implying one standard

5. emit every block, in dependency order, then STOP
- ONE fenced bash block per bucket, every variable already expanded, numbered `# BUCKET n of N`
- bucket 1 runs as written:
```bash
git switch -c "$ATOMIC_BRANCH" "$DEFAULT_BRANCH"
git add $ATOMIC_FILES
git commit -m "$ATOMIC_COMMIT" -m "$ATOMIC_DESCRIPTION"
git push -u origin "$ATOMIC_BRANCH"
gh pr create --base "$DEFAULT_BRANCH" --fill
gh pr merge --auto --rebase
git switch "$DEFAULT_BRANCH"
```
- every later bucket leads with the sync, since `--rebase` rewrote the trunk under it:
```bash
git pull --ff-only origin "$DEFAULT_BRANCH"
git switch -c "$ATOMIC_BRANCH" "$DEFAULT_BRANCH"
```
- head each later block with: "only once bucket n-1 shows merged"
- buckets marked INDEPENDENT may be pasted without waiting; say which, and never guess
- close with: paste them in order, and tell me if any CI goes red
- a red bucket invalidates the rest of the plan, since it was computed against a trunk that never
  landed — say so, and re-run `@git-deliver` rather than pasting on
- a commit message naming a destructive command trips `pretooluse.sh`, so reword rather than quote

6. check conditions before continuing:
- IF `--first` → emit only bucket 1's block and report what the remaining plan holds
- ELSE wait for the user, re-read `git status -s`, and repeat from step 2 until the tree is clean

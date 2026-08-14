---
name: deliver
model: opus
effort: high
license: MIT
compatibility: requires bash, curl, git
description: bucket uncommitted work into atomic, single-purpose PRs, gate the plan, then hand back every block of it
argument-hint: "[--help] [--debug] [--finished]"
disable-model-invocation: true
metadata:
  kind: trigger
---
**a messy tree becomes single-purpose PRs:** bucketed, ordered and written, ready to paste
- bucketing, ordering and message drafting are the reasoning it does for you
- each bucket: branch, commit, push, PR, auto-merge, then back to the trunk
- runs none of it; every bucket is a block you paste into your own terminal

# Instructions

## Telemetry
```!
"${CLAUDE_PLUGIN_ROOT}"/skills/deliver/deliver.sh $ARGUMENTS
echo "sidecar exit: $?"
```
- `help: requested` → the run was refused before it started; `## Help` below is the whole turn
- it already ran, so there is no command to issue
- fail (`sidecar exit` > 0) → abort and report: "<raw terminal error>"
- success (`sidecar exit` = 0) → capture `default branch` from the telemetry
- IF the handover block names any prep command, hand it over and WAIT before step 2
- the preflight measures only, so the tree is still wherever the user left it
- bucketing against an unsynced trunk drafts commits the user then has to redo
- IF `touches .claude/settings.json` reads `yes`, say so now: no sandboxed command can write

    that path, so the pull after the merge needs the retry hatch

1. `git status -s` and `git diff`
- analyze changes and group into self-contained atomic `type(scope)` buckets
- interdependent files needed to pass CI should be grouped together
- tests are grouped with code they validate, matched via imports, routes, selectors, etc
- types (derived from effect on behavior, in order of precedence):
  - `new` → adding a new capability that did not exist before
  - `fix` → editing an existing capability that was not working as expected
  - `improve` → editing an existing capability that changes how it works
  - `update` → editing an existing capability that doesn't change how it works
  - `debug` → logs, profiling scripts, temp instrumentation
  - `test` → test changes independent of other changes (no in-tree subject)
- scopes (derived from context of change, in order of precedence): 
  - `class` → singular noun of changed item (e.g. hook, skill, tool, etc)
  - `domain` → plural noun of multiple changed items (e.g. docs, settings, config, etc)
  - `most dominant domain` of changes spanning multiple domains
  - `misc` for changes spanning multiple unrelated domains
- titles: stated outcomes, verb first, doesn't repeat type or scope, in present tense
- examples:
  - correct: `new(skill): generate github issues report and analysis`
  - incorrect: `new(issues): operator issues skill`
  - correct: `improve(tool): migrate skill frontmatter checks to 'export-readme'`
  - incorrect: `improve(check-skills): hand frontmatter rules to export-readme`

2. plan EVERY bucket, then STOP and gate on the plan
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

3. verify every bucket before emitting a single block, since a red PR costs a round trip
- resolve every reference a bucket breaks against `git show HEAD:<file>`, NEVER the working copy
- a path the working tree already fixed still reads broken to CI until its bucket lands
- run the validators each bucket touches, plus the two checks CI runs: `shellcheck -x` and `bash -n`
- CI does not gate references, so a bucket that breaks one still goes green — the read above is the check
- bucket 1 verifies against today's HEAD; every later bucket verifies against a trunk that does not
  exist yet, so say which buckets carry that weaker guarantee rather than implying one standard

4. emit every block, in dependency order, then STOP
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
  landed — say so, and re-run `/gitgud:deliver` rather than pasting on
- recover a failed `git switch -c` with `git switch "$DEFAULT_BRANCH"`, then
  `git branch -D "$ATOMIC_BRANCH"` (add `git push origin --delete "$ATOMIC_BRANCH"` if pushed)
- a commit message naming a destructive command trips the pretooluse hooks, so reword rather than quote

5. check conditions before continuing:
- IF `--debug` → emit only bucket 1's block and report what the remaining plan holds
- IF `--finished` → bucket only finished work, then report every file left behind and why
  - finished means: no `TODO`/`FIXME`/`XXX`/`WIP` added by the change, no commented-out block left
    behind, no empty function body or `throw new Error("not implemented")`, no debug logging, and
    no file whose diff is imports-only or scaffolding with no caller
  - a file that only a finished file imports counts as finished, since shipping without it breaks
  - anything you cannot place with confidence stays UNFINISHED; the flag drains the tree partially
    on purpose, and a wrong call here ships half a feature
- ELSE wait for the user, re-read `git status -s`, and repeat from step 2 until the tree is clean

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

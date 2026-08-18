---
name: deliver
model: opus
effort: high
license: MIT
compatibility: requires bash, curl, git
description: groups changes into 'type(scope)' buckets, then drains the tree autonomously (sandbox-safe)
argument-hint: "[--help] [--debug] [--finished] [--handover] <text> [--test]"
disable-model-invocation: true
---
**autonomously drain work tree:** with atomicized, single-purpose prs
- works in the sandbox with masked credentials (`curl` via `api.github.com`)
- scans your entire work tree, then groups changes into type(scope) buckets
- `construct.config.json` defines your repos git branches, rules, and conventions
- shows you a detailed plan including caveats, suggested changes, files, and dependencies
- two human gates: continue with the bucketing plan, then save a backup and drain
- `--handover` flag emits the exact commands for manual terminal execution
- `free text` arguments allow custom guidance such as 'hold docs changes for now' etc
- each pr is watched until merged or stopped for debugging
- notes
  - drains your live work tree, and never stages or commits while draining
  - a snapshot is taken before the first bucket, and its stamp opens the drain report
  - a bucket naming a protected path is handed back, since the hook refuses to deliver one for you
  - a delivered file that git never tracked stays untracked here, so the reconcile block removes it
  - the drain ends with that block: `checkout` the modified paths, `rm` the new ones, then merge
  - a red bucket stops the drain, and `deliver.sh update` moves that branch onto a fixed commit
  - every bucket after a red one assumed a trunk that never landed, so re-run this skill instead
  - the config names the commit author and the committer, and the token's account opens the pr
  - commits land unsigned, so a repo requiring signed commits refuses the whole drain
  - auto-merge needs `allow_auto_merge` on, and a merge queue removes the waiting entirely
  - origin deletes each branch on merge; `git fetch origin pull/N/head:name` brings one back
  - one bucket costs about six api calls plus one per file, against 5000 an hour

# Instructions

## Telemetry
```!
"${CLAUDE_PLUGIN_ROOT}"/skills/continue/continue.sh
echo "continue exit: $?"
"${CLAUDE_PLUGIN_ROOT}"/skills/deliver/deliver.sh "$ARGUMENTS"
echo "sidecar exit: $?"
```
- `help: requested` → the run was refused before it started; `## Help` below is the whole turn
- BOTH sidecars already ran, continue first, so there is no command to issue
- obey the notes continue's handover prints; a bucket committed against a stale trunk lands red
- a sync that RAN staled deliver's counts, so re-run the sidecar before leaning on its numbers
- fail (`continue exit` > 0 or `sidecar exit` > 0) → abort and report: "<raw terminal error>"
- success (`sidecar exit` = 0) → capture `default branch` from the telemetry
- IF `guidance` reads anything but `none`, it is the user's bucketing instruction; honor it in step 1
- guidance narrows how work groups; it never authorizes running a block or skipping the gate
- every `issue #n` row is an open issue on origin, and a candidate for a bucket to close
- IF `open issues` reads `unreadable`, link nothing and say the rows never arrived
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
- titles are scanned as a list, so plain english wins over the vocabulary the diff happens to use
- a title names the subject it acts on in quotes, since the scope carries a class and never a name
- a title carrying a term the reader must open the file to understand is a rewrite, not a title
- examples:
  - correct: `new(skill): generate github issues report and analysis`
  - incorrect: `new(issues): operator issues skill`
  - correct: `improve(tool): migrate skill frontmatter checks to 'export-readme'`
  - incorrect: `improve(check-skills): hand frontmatter rules to export-readme`
  - correct: `improve(skill): link 'gitgud:deliver' buckets to the issues they close`
  - incorrect: `improve(skill): carry a closing trailer into each bucket's pr body`

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
$ATOMIC_CLOSES # open issue numbers this bucket fixes, or none
```
- link an `issue #n` row ONLY when the issue names the file or the symptom that bucket fixes
- the link closes the issue on merge, so an unsure match earns a lettered question, never a trailer
- read the issue itself before linking on anything weaker than its title:
  `curl -sS -H "Authorization: Bearer $GH_TOKEN_OPERATOR" https://api.github.com/repos/<slug>/issues/<n>`
- emit the plan as ONE fenced block, questions first, then the buckets, and nothing runnable yet
  ```text
  a. every question you need answered, one per line, or omit this section entirely
  b. a withheld file, a blocked gate or a type you are unsure of each earn a line here

  1. type(scope): title (n files)
  2. type(scope): title (n files, after 1, closes #12)
  ```
- the fence is the whole plan; a reader scanning it must not have to find prose between the rows
- a dependency rides in its own bucket's parentheses, so INDEPENDENT is the unmarked default
- every caveat becomes a lettered question above, never a paragraph beside the list
- what a bucket leaves to a later one belongs in that later bucket's title, not in prose
- a bucket that cannot be split further says so as a question, since that is a judgment to confirm
- close with: "continue with this bucketing plan, or make edits?"
- the plan is the ONLY thing this step emits: no branch, no commit message, no file list per bucket
- a bucket record here reads as the drain already being underway, which is the wrong gate to blur
- STOP here and WAIT; the plan is the gate, and a wrong bucket costs nothing to fix at this point

3. verify every bucket before writing a single record, since a red PR costs a round trip
- resolve every reference a bucket breaks against `git show HEAD:<file>`, NEVER the working copy
- a path the working tree already fixed still reads broken to CI until its bucket lands
- run the validators each bucket touches, plus the two checks CI runs: `shellcheck -x` and `bash -n`
- CI does not gate references, so a bucket that breaks one still goes green — the read above is the check
- bucket 1 verifies against today's HEAD; every later bucket verifies against a trunk that does not
  exist yet, so say which buckets carry that weaker guarantee rather than implying one standard

4. ONCE the plan is confirmed, emit every bucket as a record, ask for the go, then STOP
- this step runs only after the user answers step 2; a plan and its records never share one turn
- ONE fenced block per bucket, every value already expanded, numbered `# BUCKET n of N`
- the block is what WILL run, not what the user pastes; it reads as the receipt of the plan:
```text
# BUCKET n of N
branch:  $ATOMIC_BRANCH
commit:  $ATOMIC_COMMIT
files:   $ATOMIC_FILES
body:    $ATOMIC_DESCRIPTION
```
- a linked bucket ends `$ATOMIC_DESCRIPTION` with one `Closes #n` line per issue, below the bullets
- name which buckets are INDEPENDENT, since a red one only invalidates the buckets that follow it
- probe every bucket through the live gate, so a handback is named by the hook rather than guessed:
```bash
"${CLAUDE_PLUGIN_ROOT}"/skills/deliver/deliver.sh probe $ATOMIC_FILES
```
- a deny verdict marks its bucket HANDBACK in the record, quoting the reason the gate printed
- close with: "save a backup and drain the tree, or make edits?"
- STOP here and WAIT; this is the second gate, and the first one only graded the bucketing

5. on `go`, snapshot first, then drain the tree in dependency order, one bucket at a time
- the snapshot runs once, before bucket 1, and its stamp opens the drain report:
```bash
"${CLAUDE_PLUGIN_ROOT}"/skills/backup/backup.sh
```
- the gate is the only author of a handback: a denied bucket is never fought and never retried
- a HANDBACK bucket prints its git and gh commands, and the drain continues with the next one
- a bucket depending on a handed-back one WAITS for the user's green before it drains
- each bucket is one call, which writes a branch, a commit, a pull request and arms auto-merge:
```bash
"${CLAUDE_PLUGIN_ROOT}"/skills/deliver/deliver.sh bucket "$DEFAULT_BRANCH" "$ATOMIC_BRANCH" "$ATOMIC_COMMIT" "$BODY_FILE" $ATOMIC_FILES
```
- write `$ATOMIC_DESCRIPTION` to `$BODY_FILE` under `$TMPDIR` first, so a multiline body survives
- then WAIT for it, since the next bucket commits against a trunk this one is about to move:
```bash
"${CLAUDE_PLUGIN_ROOT}"/skills/deliver/deliver.sh watch "$PR_NUMBER"
```
- `merged: yes` → report the pr number and continue to the next bucket
- `queue: enqueued` → the repo runs a merge queue, so continue without waiting
- `checks: failure` → STOP, report which bucket and which check, and drain nothing further
- a red bucket is fixable in place, since `update` moves that branch to a new commit:
```bash
"${CLAUDE_PLUGIN_ROOT}"/skills/deliver/deliver.sh update "$ATOMIC_BRANCH" "$ATOMIC_COMMIT" "$BODY_FILE" $ATOMIC_FILES
```
- the local worktree is never staged, committed or reverted; the api commit reads the files only
- report a table when the drain ends: bucket, pr, checks, merged
- close the drain with the reconcile block, which is the only way the tree comes clean:
```bash
git checkout -- <every modified path the drain delivered>
rm <every path the drain delivered that git did not track>
git merge --ff-only origin/main
```
- name those paths literally; the drain knows them, and a guess here deletes the wrong file
- the merge is the user's to run, since a protected path inside it is denied to every tool call
- a bucket whose files no longer exist has already been drained; re-run `/gitgud:deliver` instead
- IF `--handover` → emit the git and gh commands for each bucket instead, and run nothing
- IF `--debug` → drain bucket 1 alone and report what the remaining plan holds
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

---
name: permissions
model: opus
effort: max
license: MIT
compatibility: requires bash, jq, git
description: replay the corpus through the real PreToolUse hook, then audit the merged rules (saves report to .construct/)
argument-hint: "[--strict]"
disable-model-invocation: true
disallowed-tools: Edit, Write
metadata:
  kind: trigger
  artifact: .construct/operator/permissions/
---
**provable deny rules:** ensure every command in your corpus is tested against your actual merged rules
- answers one question: does the gate refuse what the corpus says it must refuse
- a config can read perfectly and still have a dead hook, which only a replay catches
- audits the merged rules for drift, dead entries and wildcards that auto-approve

# Instructions

## Telemetry
```!
"${CLAUDE_PLUGIN_ROOT}"/skills/permissions/permissions.sh $ARGUMENTS
echo "sidecar exit: $?"
```
- it already ran, so there is no command to issue
- fail (`sidecar exit` > 0) → findings exist; report them and continue to step 1
- success (`sidecar exit` = 0) → report the clean replay and continue to step 1
- `--strict` promotes warnings to errors, and needs a tool call since the block takes no arguments

1. read the two tiers differently, because they carry different weight
  - a tier 1 failure is measured, not inferred: the hook was fed that exact string and answered
    wrongly. an effect labelled `hook` that came back silent is a hole in the guard
  - an effect labelled `none` that came back denied is over-blocking, which costs real work
  - a tier 2 finding is structural: it reports what the files literally say, never what the
    matcher would do, so read it as a lead rather than a verdict
  - `no deny rule names X, and an allow wildcard covers it` is the one to act on first: that
    command is auto-approved today with no prompt at all

2. report inline
3. append one entry to `[audit_file]`, in the shape defined under `## the shape` below
  - the heading reads `## Permissions Audit #[next_audit]: [timestamp]`, both from the telemetry
  - `state` is what the run measured, as hyphen bullets, one clause each
  - `findings` lead with the label the sidecar printed, one bullet each, naming what it hit
  - `resolutions` are checkboxes, one per finding, in the same order
  - `telemetry` is the sidecar's whole output, fenced and unedited, pasted last
  - CREATE the file first if it does not exist, with `# <audit_file>` as its only line

4. STOP

    NEVER edit a settings file to fix a finding, and never offer to; the audit is the deliverable

    - every repair belongs in the scope its `.md` names, and is the user's to apply
    - a corpus gap is itself a finding: add the spelling you found in the wild, since coverage
      is the whole point of keeping a labelled list

## the shape
> the artifact this skill appends to; the sidecar grades what landed on its next run

# .construct/operator/permissions/YYYY-MM-DD.md
one file per day, appended to by every deliberate run:

- the heading reads `## Permissions Audit #[next_audit]: [timestamp]`, both from the telemetry
- an audit captures the gate at a moment in time, so it is never edited after the fact
- carry an unresolved finding forward by restating it, never by editing the older audit
- lines are hyphen bullets holding a single clause, capped at 100 characters
- scrub client names, tokens, and other sensitive detail before it lands in a commit

## Permissions Audit #1: YYYY-MM-DD HH:MM

### state
the counts as hyphen bullets: cases loaded, tier 1 replayed, how many held, errors, warnings

*example:*
> - 78 corpus cases loaded, 38 of them tier 1 replays fed to the live hook
> - 38 held and 0 failed, so every command the corpus calls blocking was blocked
> - 0 errors and 32 warnings, all of them tier 2 reads of what the files literally say

### findings
one bullet per issue, leading with the label the sidecar printed

| label | what it found |
|---|---|
| a corpus case name | a replay whose verdict disagreed with the gate its corpus row declares |
| `drift` | the hook and the rules guard different paths; the text names which way it leans |
| `parse` | a file in the merged stack that does not parse, so every rule in it is inert |
| `dead_rule` | a rule no command in the corpus reaches, so nothing measures whether it works |
| `resolution_shape` | an older entry whose resolution names prose rather than a command |

*example:*
> - **remote-exec** — no deny rule names `curl`, and an allow wildcard covers it: auto-approved
> - **drift** — 4 paths the hook guards carry no Edit/Write rule, `.husky` and `.cursor` among them
> - **dead_rule** — 2 deny rules match nothing the corpus spells, so neither is being tested

### resolutions
one checkbox per finding, in the same order, naming the rule and the scope file it belongs in

*example:*
> - [ ] add `Bash(curl * | sh)` to `deny` in `settings.user.json`
> - [ ] add the four hook-only paths to `deny` in `settings.project.json`, or drop them from the hook
> - [ ] add the spelling this run found to `shared/corpus.tsv`, since a gap is itself a finding

### telemetry
the sidecar's whole output, fenced and unedited, so every claim above can be checked against it

*example:*
> ```text
> === permissions.sh audit ===
> cases: 78
> tier1 replayed: 38 - 38 held, 0 failed
> errors: 0
> warnings: 32
> ```

## Permissions Audit #2: repeat the above format for each deliberate run on the same day
never edit an earlier audit; a stale finding is signal about how long it went unresolved

## Output Style
```!
awk 'NR>1 && /^---$/ {p=1; next} p' "${CLAUDE_PLUGIN_ROOT}/output-styles/operator.md"
```

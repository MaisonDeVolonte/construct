---
name: audit
description: "Read-only whole-repo condition: composition, skill pairing, manifest agreement, artifact freshness."
disable-model-invocation: true
metadata:
  kind: trigger
---
**/gitgud:audit:** Run ONLY on explicit `/gitgud:audit` command
- read-only: it counts and compares, and never mutates a tracked file
- reports what a fresh clone would load, then where the tree has drifted from what the docs claim
- branch, remote and team state belong to `triage.sh`, so this never re-walks a branch
- outputs a numbered condition list, each finding with the command that shows the detail

## voice

```!
awk 'NR>1 && /^---$/ {p=1; next} p' "${CLAUDE_PLUGIN_ROOT}/output-styles/operator.md"
```

- the block above already ran, and it is the output contract for this response
- it holds for this turn even when the user's active output style is something else
- an empty block means the plugin has no style file; continue, since voice never gates the work

## telemetry

```!
"${CLAUDE_PLUGIN_ROOT}"/skills/audit/audit.sh
echo "sidecar exit: $?"
```

1. read the block above; it already ran, so there is no command to issue
  - fail (`sidecar exit` > 0) → abort and report: "<raw terminal error>"
  - success (`sidecar exit` = 0) → continue to step 2

2. grade each section, and report ONLY what is off; a healthy section earns one line, not a table
  - `composition` → a plugin with 0 skills is a load failure, never an empty plugin
  - `pairing` → any non-zero orphan count is a broken trigger or dead code, never a style nit
  - `manifests` → a version of `unset` pins nothing, so every commit reads as a new release
  - `manifests` → catalog entries fewer than plugins means an installed bundle cannot resolve
  - `shared` → any drift is an ERROR, since duplication only holds while the copies agree
  - `shared` → a copy count below the plugin count means a plugin cannot reach the library at all
  - `artifacts` → a directory whose latest file predates the last week means its writer stalled

3. output a numbered condition list, worst first
  - each entry names the finding, why it matters, and the one command that shows the detail
  - say plainly when a section is clean rather than padding the list to look thorough
  - never propose a fix the telemetry does not support; an unread directory is not a stale one

4. append one entry to `[audit_file]`, in the shape defined under `## the shape` below
  - the heading reads `## Git Audit #[next_audit]: [timestamp]`, both from the `archive` section
  - `state` is what the run measured, as hyphen bullets, one clause each
  - `findings` lead with the label this doc assigns, one bullet each, naming what it hit
  - `resolutions` are checkboxes, one per finding, in the same order
  - `telemetry` is the sidecar's whole output, fenced and unedited, pasted last
  - CREATE the file first if it does not exist, with `# <audit_file>` as its only line

5. close with the two reads this sidecar deliberately does not perform
  - `bash plugins/gitgud/shared/triage.sh` for branch, remote and team state
  - `bash .claude/skills/skills/skills.sh` for the graded shape errors behind `pairing`

## the shape
> the artifact this skill appends to; the sidecar grades what landed on its next run

# .construct/gitgud/audit/YYYY-MM-DD.md
one file per day, appended to by every deliberate run:

- the heading reads `## Git Audit #[next_audit]: [timestamp]`, both from the telemetry
- an audit captures the repo at a moment in time, so it is never edited after the fact
- carry an unresolved finding forward by restating it, never by editing the older audit
- lines are hyphen bullets holding a single clause, capped at 100 characters
- scrub client names, tokens, and other sensitive detail before it lands in a commit

## Git Audit #1: YYYY-MM-DD HH:MM

### state
the counts as hyphen bullets: what the tree is made of, and what each section measured

*example:*
> - 78 tracked files across 3 plugins, carrying 19 skills and 6 hooks
> - 19 skill docs, 0 missing a sidecar and 0 sidecars missing a doc
> - 3 secrets.sh copies, all byte identical, against 3 plugins

### findings
one bullet per issue, leading with the label this doc assigns

| label | what it found |
|---|---|
| `Load Failure` | a plugin reporting 0 skills, which is a load failure and not an empty plugin |
| `Orphan Pair` | a doc with no sidecar, or a sidecar with no doc |
| `Unpinned Version` | a manifest version of `unset`, so every commit reads as a new release |
| `Catalog Gap` | fewer catalog entries than plugins, so an installed bundle cannot resolve |
| `Shared Drift` | the `secrets.sh` copies disagree, which duplication only survives while they match |
| `Missing Copy` | fewer copies than plugins, so a plugin cannot reach the library at all |
| `Stale Artifact` | a kind whose newest file is old, meaning its writer stopped being run |

*example:*
> - **Shared Drift** — 2 versions across 3 secrets.sh copies; retardify holds the stale one
> - **Stale Artifact** — `.construct/operator/credentials/` has not been written since 2026-08-01
> - **Unpinned Version** — gitgud and retardify both carry `version: unset`

### resolutions
one checkbox per finding, in the same order, naming the command that closes it

*example:*
> - [ ] `bash .claude/skills/secrets/secrets.sh --write` to repoint the copies at the canonical
> - [ ] `/operator:credentials` to refresh the kind, or accept in writing that it is dormant
> - [ ] set a real `version` in both manifests, then `claude plugin tag` each one

### telemetry
the sidecar's whole output, fenced and unedited, so every claim above can be checked against it

*example:*
> ```text
> --- pairing ---
> skill_docs: 19
> docs_missing_sidecar: 0
> --- archive ---
> audit_file: .construct/gitgud/audit/YYYY-MM-DD.md
> next_audit: 1
> ```

## Git Audit #2: repeat the above format for each deliberate run on the same day
never edit an earlier audit; a stale finding is signal about how long it went unresolved

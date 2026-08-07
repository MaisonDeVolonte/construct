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

4. close with the two reads this sidecar deliberately does not perform
  - `bash plugins/gitgud/shared/triage.sh` for branch, remote and team state
  - `bash tools/check-skills/check-skills.sh` for the graded shape errors behind `pairing`

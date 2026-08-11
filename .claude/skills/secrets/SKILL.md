---
name: secrets
description: "The rule every secrets.sh copy holds: one canonical file, byte-identical siblings, repaired rather than merged."
when_to_use: "Editing plugins/*/shared/secrets.sh, adding a credential pattern, or resolving a /gitgud:audit drift finding. Also when adding a plugin that needs the shared scan."
metadata:
  kind: spec
---
# secrets

## the shape
`secrets.sh` is one file that has to exist in three places at once:

- a plugin install copies that plugin's own directory and never a sibling, so the file cannot be shared
- the copies are byte-identical by contract, and `/gitgud:audit` reports the moment one drifts
- `plugins/operator/shared/secrets.sh` is canonical, since operator is the bundle every install pulls
- siblings are discovered by glob, so a new plugin is covered without editing this tool
- a stale copy is replaced whole; there is no merge, since two edited copies is a mistake not a branch

## the two modes
- `--check` is the default, mutates nothing, and exits 1 on any drift; this is the mode ci runs
- `--write` overwrites every stale sibling from the canonical, and never edits the canonical itself
- edit the canonical, run `--write`, commit all three together — one edit reaching one file is the bug

## why a tool rather than three edits
a three-file synchronized edit is the exact shape that drifts, and this repo has already paid for it
once: a path constant written without its separator survived a bulk rewrite that fixed every other
copy. the drift check existed before this tool did, which caught the divergence but never repaired
it, and `/gitgud:audit` is read-only by posture so the repair could not live there.

```text
VERIFY - not part of the artifact
- RUN `.claude/skills/secrets/secrets.sh` after editing any `secrets.sh`; it defaults to --check
- FIX drift with `--write`, then re-run `--check` and confirm it reports none
- RE-RUN every sidecar that sources the file, since a pattern change moves their findings
- COMMIT all three copies in one commit; a partial commit reintroduces the drift it just fixed
```

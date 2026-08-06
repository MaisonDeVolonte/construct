---
name: doc-credentials
description: Shape of a dated credential audit in docs/credentials/, written by /test-credentials.
metadata:
  kind: spec
---
```javascript
/**
 * ==========================================
 * @file SKILL.md - credential audit template
 * ==========================================
 * @description
 * FILE
 * - one file per day, `docs/credentials/`, named `YYYY-MM-DD.md`
 * - gitignored with the rest of `docs/`, and it stays that way; this one names live secrets
 * - NEVER contains a usable credential value
 * - a `fingerprint` of four leading and four trailing characters is the ONE exception, so a
 *   reader can match a row to the credential in their hand; it sits under every length in
 *   `SECRET_PATTERNS`, and the sidecar re-runs the detector on the fragment before printing it
 * - a run that could not grade writes no file at all, since an ungraded run proves nothing
 * BODY
 * - `unruled` leads, since it is the only section that holds work
 * - `masked` and `unset` follow as evidence, one row per vector
 * - `files` closes it, since a denied path that became readable is the loudest possible finding
 * - every verdict is one of: masked, unset, leaked, present, denied, readable, unreadable
 * VERIFY
 * - `AGENTS/skills/doc-credentials/doc-credentials.sh` asserts no value ever reached the file
 * @see AGENTS.md, AGENTS/skills/doc-credentials/doc-credentials.sh,
 *      AGENTS/skills/test-credentials/SKILL.md, docs/credentials/
 */
```

# docs/credentials/YYYY-MM-DD.md

## Verdict
one line: the boundary holds, or these credentials need rotating first

## Unruled
credential-shaped variables that no rule names, so every sandboxed command can read them:

| variable | fingerprint | evidence | action |
|---|---|---|---|
| `NAME` | `abcd…wxyz` | provably a credential | rotate, then add a rule |
| `NAME` | `abcd…wxyz` | named like a credential | confirm, then rule it |

## Masked
a mask keeps the capability and hides the value, so the tool still authenticates.
a fingerprint reading `fake…` is the sentinel, which is the mask proving itself:

| variable | fingerprint | shell | printenv | env | export | subprocess | xtrace | dump | verdict |
|---|---|---|---|---|---|---|---|---|---|
| `NAME` | `fake…wxyz` | masked | masked | masked | masked | masked | masked | masked | ok |

## Unset
a deny removes the variable, so the tool loses the capability along with the secret.
an unset variable has nothing to fingerprint, so its cell reads `-`:

| variable | fingerprint | shell | printenv | env | export | subprocess | xtrace | dump | verdict |
|---|---|---|---|---|---|---|---|---|---|
| `NAME` | `-` | unset | unset | unset | unset | unset | unset | unset | ok |

## Files
| path | result |
|---|---|
| `~/.example` | denied |

## Notes
1. numbered, so `(see #1)` resolves; this is where a caveat about a probe belongs
2. name the sandbox state the run measured, since a verdict outside it means nothing

```text
VERIFY - not part of the artifact
- RUN `AGENTS/skills/doc-credentials/doc-credentials.sh` after any report lands
- STOP on a `secret` finding and rotate that credential before anything else; the file leaked it
- FIX every ERROR, since each one breaks a rule stated in the header above
- ANSWER the checklist it prints, since those rules are the ones no script can judge
```

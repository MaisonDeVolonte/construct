---
name: credentials
description: Probe every credential-shaped variable in this sandboxed shell across 19 injected, masked and denied vectors, then save a dated report to .operator/credentials/ naming every leak to rotate first.
argument-hint: "[--strict] [--quick]"
disable-model-invocation: true
disallowed-tools: WebFetch, WebSearch
model: opus
effort: max
license: MIT
metadata:
  kind: trigger
  artifact: .operator/credentials/
---
**/operator:credentials:** the frontmatter blocks every path except an explicit invocation
- proves the masking story rather than asserting it, across every vector an agent could reach
- `mask` hides the value and keeps the capability; `deny` hides it by removing the variable
- an unruled credential is the finding that matters: it needs a rule AND a rotation

## telemetry

```!
"${CLAUDE_PLUGIN_ROOT}"/skills/credentials/credentials.sh $ARGUMENTS
echo "sidecar exit: $?"
```

1. read the block above; it already ran, so there is no command to issue
  - fail (`sidecar exit` > 0) → abort and report the raw terminal error inside a markdown code block
  - `credential layer active: no` → say so and STOP; it ran outside the sandbox and every verdict
    there is meaningless, so report nothing as passing or failing
  - success (`sidecar exit` = 0) → continue to step 2

2. write the report to `.operator/credentials/YYYY-MM-DD.md`, following `plugins/operator/skills/credentials/SKILL.md`
  - NEVER quote, echo or paste a credential value into the report, the chat, or anywhere else
  - a `leaked` classification means the probe recovered the real thing: name the variable and the
    vector, and say nothing about what it contained
  - lead with the unruled list, since that is the only section holding work
  - append; a dated report is evidence of what was true that day and is never rewritten

3. close with the two-line verdict the user actually needs:
  - every ruled credential came back masked or unset, so the boundary holds
  - OR these named credentials did not, and each one needs rotating before it is ruled

    a `LEAKED` verdict means that credential has been exposed to every sandboxed command since it
    was set. rotation comes FIRST and the rule comes second; a rule over a burned secret is theatre.

## the shape
> the spec this skill writes against; the validator below grades what landed

# .operator/credentials/YYYY-MM-DD.md
one file per day, written by `/operator:credentials`, appended to and never rewritten:

- gitignored with the rest of `.operator/`, and it stays that way; this one names live secrets
- it NEVER contains a usable credential value, in any section, for any reason
- a `fingerprint` of four leading and four trailing characters is the ONE exception, so a
  reader can match a row to the credential in their hand; it sits under every length in
  `SECRET_PATTERNS`, and the sidecar re-runs the detector on the fragment before printing it
- a run that could not grade writes no file at all, since an ungraded run proves nothing
- `unruled` leads, since it is the only section that holds work
- `masked` and `unset` follow as evidence, one row per vector
- `files` closes it, since a denied path that became readable is the loudest possible finding
- every verdict is one of: masked, unset, leaked, present, denied, readable, unreadable

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
a fingerprint whose leading characters spell the sentinel is the mask proving itself:

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

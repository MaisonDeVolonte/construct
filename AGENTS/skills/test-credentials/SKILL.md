---
name: test-credentials
description: Prove every credential is masked, unset, or unruled by probing the live sandbox across every exfiltration vector, then save the report.
disable-model-invocation: true
metadata:
  kind: trigger
---
**/test-credentials:** the frontmatter blocks every path except an explicit invocation
- proves the masking story rather than asserting it, across every vector an agent could reach
- `mask` hides the value and keeps the capability; `deny` hides it by removing the variable
- an unruled credential is the finding that matters: it needs a rule AND a rotation

## telemetry

```!
"${CLAUDE_PLUGIN_ROOT}"/skills/test-credentials/test-credentials.sh
echo "sidecar exit: $?"
```

1. read the block above; it already ran, so there is no command to issue
  - fail (`sidecar exit` > 0) → abort and report the raw terminal error inside a markdown code block
  - `credential layer active: no` → say so and STOP; it ran outside the sandbox and every verdict
    there is meaningless, so report nothing as passing or failing
  - success (`sidecar exit` = 0) → continue to step 2

2. write the report to `docs/credentials/YYYY-MM-DD.md`, following `AGENTS/skills/doc-credentials/SKILL.md`
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

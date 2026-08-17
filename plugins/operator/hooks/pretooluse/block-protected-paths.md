---
name: block-protected-paths
description: denies bash writers, heredocs and redirects aimed at settings, hooks and other policy paths
---

**the write the Edit rules never see:** bash reaches policy files, so this gate reads bash
- depends on no sibling plugin; needs `shared/commands.sh` beside it, and `jq`
- decides one thing: does an unquoted segment aim a writer, heredoc or redirect at a policy path
- an interpreter beside a policy path counts as a writer, and a runtime-resolved target denies
- splits compounds on unquoted `&|;` only, so a quoted `sed 's|a|b|'` cannot tear itself apart
- costs one process spawn per Bash call, measured at roughly 60ms

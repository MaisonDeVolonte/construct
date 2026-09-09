---
name: block-untracked-exec
description: denies running a script no commit holds, since its contents are opaque to a matcher
---

**a script's bytes cannot be matched, so provenance is judged instead:** git decides
- depends on no sibling plugin; needs `shared/commands.sh` beside it, `git`, and `jq`
- decides one thing: has git stored what this segment is about to execute, unchanged
- two calls answer it: `git ls-files --error-unmatch`, then `git diff --quiet HEAD`
- covers `./x`, `bash x`, `sh x`, `source x`, `make`, and the package-manager install forms
- an install denies without `--ignore-scripts`, since a tracked manifest never vouches for a postinstall
- outside a git repo it exits silently, since the premise it tests is absent there
- costs one process spawn per Bash call, plus two git calls only when a target is named

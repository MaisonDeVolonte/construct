---
name: block-outside-moves
description: denies any mv whose destination lands outside the repo, where git cannot recover it
---

**a move out of the repo deletes it from git's reach:** nothing staged survives, so it denies
- depends on no sibling plugin; needs `shared/commands.sh` beside it, and `jq`
- decides one thing: does an `mv` segment's destination resolve outside the repo root
- an in-repo rename passes silently, so ordinary refactors never pay for the check
- costs one process spawn per Bash call, measured at roughly 60ms

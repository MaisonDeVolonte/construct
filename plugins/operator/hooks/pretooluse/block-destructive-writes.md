---
name: block-destructive-writes
description: denies write shapes that leave no undo, on any path rather than only a protected one
---

**a write with no undo is refused wherever it lands:** the path never enters the decision
- depends on no sibling plugin; needs `shared/commands.sh` beside it, and `jq`
- decides one thing: does a Bash segment carry a write whose previous bytes survive nowhere
- five classes: in-place editors, truncators, metadata flips, clobbering copies, fetch-to-file
- a single `>` denies only when its target already exists, so `>>` and new files pass
- `rm` is deliberately absent, since a single-file delete is ordinary and `rm -r` is already denied
- the sibling `block-protected-paths.sh` asks where a write lands; this one asks what it does
- costs one process spawn per Bash call, measured at roughly 60ms

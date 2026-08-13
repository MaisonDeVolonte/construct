---
name: block-destructive-git
description: denies force pushes, force branch deletes, non-ff merges and unsafe switches before bash runs them
---

**the four git verbs that lose work:** denied on the whole string, handed back to the user
- depends on no sibling plugin; one self-contained file plus `jq`
- decides one thing: does the command carry a destructive git shape anywhere in its string
- force push, force branch delete, a merge without `--ff-only`, a switch that creates or discards
- deny rules are prefix-anchored and miss trailing flags, which is the gap this action closes
- costs one process spawn per Bash call, measured at roughly 60ms

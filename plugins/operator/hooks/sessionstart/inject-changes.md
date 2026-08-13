---
name: inject-changes
description: injects the dirty working tree with ages and owners, so agents notice each other
---

**who else is in this tree:** every pre-session dirty path belongs to another agent
- depends on no sibling plugin; one self-contained file plus `jq` and git
- prints the branch, up to 20 dirty paths with coarse ages, then stash and worktree counts
- closes on the directive that stops a foreign stage, revert or commit
- costs one process spawn and a `git status` per session start

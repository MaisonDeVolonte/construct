---
name: inject-readme
description: injects the readme into opening context, trimmed to the harness's per-payload cap
---

**sessions start briefed, never blank:** the readme lands whole or announces its own cut
- depends on no sibling plugin; one self-contained file plus `jq`
- injects README.md up to a 9500-byte budget, cut on a line boundary and announced
- an unbudgeted payload is truncated to a 2KB preview the session never reads, so the budget is
  what makes the injection real rather than nominal
- a missing readme injects nothing; costs one process spawn per session start

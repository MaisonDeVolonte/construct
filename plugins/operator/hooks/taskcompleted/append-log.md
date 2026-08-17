---
name: append-log
description: blocks a completing task until a note lands in today's log, and does nothing else
---

**the log is a precondition, not a chore:** no task closes on unwritten work
- depends on no sibling plugin; takes the note's shape from `/operator:logs`
- blocks with the ask; the agent is what writes, which is why the name says demand
- a missing log file is treated as nothing, since `inject-log` owns the stub
- costs one process spawn per completed task

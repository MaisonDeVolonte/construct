---
name: demand-log-note
description: blocks a completing task until a note lands in today's log, and does nothing else
---

**the log is a precondition, not a chore:** no task closes on unwritten work
- depends on the retardify plugin's log spec for the note's shape, `/retardify:log`
- blocks with the ask; the agent is what writes, which is why the name says demand
- a missing log file is treated as nothing, since `inject-logs` owns the stub
- costs one process spawn per completed task

---
name: retardify-file
description: returns file-shape findings as context after each write, capped and truncation-honest
---

**the shape around the logic:** findings come back as context, and the agent fixes them next turn
- depends on the retardify plugin: it runs `/retardify:file`'s sidecar, and degrades without it
- carries its own cap of 10 findings, independent of its siblings, and says how many it hid
- silent when nothing is wrong, so a clean file costs one exit and no context
- costs one process spawn plus one sidecar run per write

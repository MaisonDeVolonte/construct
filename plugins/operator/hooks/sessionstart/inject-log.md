---
name: inject-log
description: injects the newest log threads into opening context, and stubs today's log file
---

**yesterday never needs re-explaining:** the newest threads carry forward across days
- depends on no sibling plugin; reads `/operator:logs`'s budget, and defaults to 4 threads without it
- injects the newest threads whole, dropping the oldest until the payload fits its cap
- stubs today's log file, the one action that still does; the demand actions rely on that stub
- costs one process spawn per session start, plus one budget read

---
name: demand-log-synthesis
description: blocks a closing turn while today's log carries pending notes or oversized threads
---

**a day of notes ends synthesized:** the log's state decides when, never a clock alone
- depends on the retardify plugin's log spec and byte budget, `/retardify:log`
- greppable state decides: pending notes and oversized threads, debounced five minutes
- an hourly full pass backstops what no grep can see; a missing log asks for nothing
- costs one process spawn and a few greps per turn end

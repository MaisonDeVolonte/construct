---
name: synthesize-log
description: blocks a closing turn while today's log carries pending notes or oversized threads
---

**a day of notes ends synthesized:** the log's state decides when, never a clock alone
- depends on no sibling plugin; takes the log spec and byte budget from `/operator:logs`
- greppable state decides: pending notes and oversized threads, debounced five minutes
- an hourly full pass backstops what no grep can see; a missing log asks for nothing
- costs one process spawn and a few greps per turn end

---
name: retardify-output
description: grades the turn's reply through /retardify:output and blocks on hard style findings
---

**the reply is graded before the turn ends:** hard style findings block, and only once each
- depends on the retardify plugin: it runs `/retardify:output`'s sidecar, and degrades without it
- blocks on hard findings only; a hash stamp keeps one reply from blocking twice
- `.construct/operator/style/off` kills the gate; a 3-block streak trips its breaker
- costs one process spawn and one transcript read per turn end

---
name: inject-support
description: injects how to report a plugin defect, branching on source checkout versus install
---

**where this plugin lives decides how a defect gets fixed:** edit the source, report the install
- depends on no sibling plugin; one self-contained file plus `jq`
- source mode fires when the plugin tree sits under the project root, and nudges for an issue
- install mode names the version and the pinned commit read from the marketplace ledger
- states the real failure: an update strands a local patch in an old version directory
- hands the agent a `gh issue create` shape plus the url fallback, and keeps filing optional
- costs one process spawn and two `jq` reads per session start

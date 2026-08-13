---
name: eslint
description: runs eslint --fix on every js, jsx, ts and tsx write, silently and in place
---

**mechanical fixes before human ones:** what a formatter can fix never reaches the linters
- depends on no sibling plugin; uses `npx eslint` when the host project carries one
- decides nothing: fixes land in place, and unfixable findings stay for the linters
- silent for every other file type, and silent when eslint is absent
- costs one process spawn per write, plus eslint's own runtime on matching files

---
name: suggest-allow-rules
description: names the allow rule a command needs when a documented shape prompts despite the rules
---

**the prompt no settings file explains:** three shapes prompt even under a matching prefix rule
- depends on no sibling plugin; needs `shared/commands.sh` beside it, and `jq`
- decides one thing: is this command about to prompt for a reason the allow list cannot show
- an unquoted glob beside `find`, `sort`, `sed` or `git`, since the glob could expand into a flag
- an exec wrapper, `watch`, `setsid`, `ionice` or `flock`, which runs whatever follows it
- `find -exec` and `find -delete`, the two forms `Bash(find *)` is documented not to cover
- casts no vote, since a hook `allow` never beats an `ask` or a `deny` rule
- prints the paste-ready rule as `systemMessage`, then logs it for `/operator:permissions` to rank
- costs one process spawn per Bash call, plus one awk pass per compound segment

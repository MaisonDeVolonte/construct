# Contributing
> strict, atomic, continuously integrated, trunk-based development with release management

```text
[atomic prs → ci checks → trunk merge] --> [main:production → deploy → github]
```

- `main` is the long-lived integration trunk; continuously synced and always releasable
- `branches` are short-lived, rarely stacked, and cut from a conflict-free trunk
- `wip` are integrated via runtime feature flags, not long-lived branches
- `commits` are structured as 'type(scope): title' with '- hyphen-delimited, multiline descriptions'
- `prs` are autonomously staged, branched, and shipped via [/gitgud:deliver](plugins/gitgud/skills/deliver/SKILL.md)
- `ci` checks shell, syntax, skills, sidecars, version, and readme before merging
- `merges` are automatic and ghost branches are pruned via [/gitgud:prune](plugins/gitgud/skills/prune/SKILL.md)
- `production` is a decoupled release branch used to manage live deployments
- `deploys` are executed via 'github actions' and triggered via [/push-release](.claude/skills/push-release/SKILL.md)

## Agents
> the sandbox denies policy edits outright and heavily gates destructive changes 

- `/fewer-permissions-prompts` is a built-in claude code skill that helps identify superfluous prompting
- `/operator:permissions` is our internal tool that checks permissions against the sandbox policy
- blocked paths:
  - `~/.claude/`
  - `.claude/settings.json` and `.claude/settings.local.json`
  - `.claude/hooks/**` and `plugins/*/hooks/`

## Gates
> all ci gates run on the pr and `gh pr merge --auto` waits for them

| gate | what fails it |
|---|---|
| `shellcheck` | any warning in a script under `plugins/` or `.claude/skills/` |
| `syntax` | a script that does not parse under `bash -n` |
| `free-text arguments survive a quote` | an unquoted `$ARGUMENTS`, which dies on the apostrophe in `don't` |
| `skill pairs validate` | a `SKILL.md` and its sidecar disagreeing on shape, name or frontmatter |
| `version files agree` | the four version files carrying different strings |
| `readme drift` | an exported region edited in the copy instead of at its source |
| `sidecars stay read-only` | a bare mutating git verb inside a sidecar |

## Releases
> the `/push-release` skill is the only thing that writes a version

- `MAJOR.MINOR.PATCH`, stored in four files, moved by a person, and `--patch` is the default
- a merge to `production` is the release, and the bumped version is what fires `/plugin update`
- release notes generate from the commits, so there is no `CHANGELOG.md` to update
- read `.claude/skills/push-release/SKILL.md` for the scheme and every preflight it refuses on

## Skills
> all skills are paired with bash sidecars for deterministic output and artifact validation

- a mutating command is emitted through `handover_cmd` for a person to read and paste
- `metadata.kind` is declared, `trigger` or `spec`, and a trigger sets `disable-model-invocation`
- run `bash .claude/skills/validate-skills/validate-skills.sh` before opening the pr
- maintainer tools are stored in the repo root's `.claude/skills/` folder


## Docs
> the root `README.md` is the source of truth and `export-readme` pushes it out to each plugin folder

- plugin readme files, skill frontmatter, and output styles are all exported from the root README.md file
- `readme drift` gates every pr ensuring all downstream docs are fully in sync

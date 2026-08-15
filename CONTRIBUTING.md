# Contributing

This repo carries a permission floor, hooks that block edits, and seven ci gates. Most of what
follows is not guessable from the tree, which is why it is written down.

## Branches

- branch off `main`, which is the integration trunk and where every pr lands
- `production` is release-only and never receives a direct commit, since it must stay a
  fast-forward of `main`; one commit landing there ends every later `merge --ff-only`
- one pr does one thing; `/gitgud:deliver` reads the working tree and writes the whole sequence

## The gates

All seven run on the pr, and `gh pr merge --auto` waits for them.

| gate | what fails it |
|---|---|
| `shellcheck` | any warning in a script under `plugins/` or `.claude/skills/` |
| `syntax` | a script that does not parse under `bash -n` |
| `free-text arguments survive a quote` | an unquoted `$ARGUMENTS`, which dies on the apostrophe in `don't` |
| `skill pairs validate` | a `SKILL.md` and its sidecar disagreeing on shape, name or frontmatter |
| `version files agree` | the four version files carrying different strings |
| `readme drift` | an exported region edited in the copy instead of at its source |
| `sidecars stay read-only` | a bare mutating git verb inside a sidecar |

## Skills

A skill is a pair: `SKILL.md` and a sidecar of the same name as its folder.

- the sidecar measures and hands over; it never mutates the tree, which the last gate enforces
- a mutating command is emitted through `handover_cmd` for a person to read and paste
- `metadata.kind` is declared, `trigger` or `spec`, and a trigger sets `disable-model-invocation`
- run `bash .claude/skills/validate-skills/validate-skills.sh` before opening the pr
- `.claude/skills/` holds maintainer tools for this repo only; they ship to nobody and the pair
  checks never walk them, so they are gated by `shellcheck` and `bash -n` alone

## The README

Never edit `plugins/*/README.md`. All three are whole-file copies of the root `README.md`.

- `.claude/skills/export-readme/` owns every managed region and writes all three copies
- edit the root, run `bash .claude/skills/export-readme/export-readme.sh`, commit what it wrote
- skill frontmatter, both output styles and the secrets file are exported the same way
- the `readme drift` gate exists because three identical copies drift apart without one

## What an agent cannot do here

The floor denies some paths outright, so a change to one arrives as a paste rather than an edit.

- `plugins/*/hooks/`, `plugins/operator/settings/` and `plugins/operator/lib/`
- the five probe skills: `setup`, `credentials`, `permissions`, `scripts`, `settings`
- `.claude/settings.json` and anything under `~/.claude/`
- `rm`, `git push`, `git config` and the other destructive verbs
- this is deliberate; if a change needs one of them, say so in the pr rather than working around it

## Releases

`.claude/skills/push-release/` is the only thing that writes a version.

- `MAJOR.MINOR.PATCH`, stored in four files, moved by a person, and `--patch` is the default
- a merge to `production` is the release, and the bumped version is what fires `/plugin update`
- release notes generate from the commits, so there is no `CHANGELOG.md` to update
- read `.claude/skills/push-release/SKILL.md` for the scheme and every preflight it refuses on

## Artifacts

`.construct/` is gitignored and holds the plans, logs and audits the skills write. Nothing in it is
required for a pr, and nothing in it should be added to one.

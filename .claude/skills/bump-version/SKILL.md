---
name: bump-version
description: "Derives the repo version from git: minor counts the plugins, patch counts commits since that tag."
argument-hint: "[--help] [--minor] [--major] [--repair]"
when_to_use: "Cutting a release, syncing the three plugin manifests, adding a plugin tree, or answering what version this repo is on. Also when a manifest version and the git tags disagree."
metadata:
  kind: spec
---
# Instructions

## the scheme
`vMAJOR.MINOR.PATCH`, where two of the three fields are counts rather than decisions:

- MAJOR stays `0` until the marketplace is a public commitment; nothing here moves it yet
- MINOR is the plugin count, so it moves only on the commit that adds a plugin tree
- PATCH is `git rev-list --count <minor tag>..HEAD`, derived on every run
- a reader can therefore price a version without a changelog: `v0.3.66` is three plugins, 66 commits on
- the history is linear, zero merges, so an ordinal is unambiguous and `--first-parent` is moot

## the tags
only MINOR tags exist as refs; PATCH is computed and never written:

- a patch tag would become the newest tag and reset the count `git describe` returns
- that is why the anchor lookup carries `--match 'v[0-9]*.[0-9]*.0'` rather than reading any tag
- the four anchors were cut retroactively, annotated, and retro-dated through `GIT_COMMITTER_DATE`
- `v0.0.0` fe9b506, the rulebook before any plugin; `v0.1.0` 63c8d3b gitgud; `v0.2.0` 2dbd3f2
  retardify; `v0.3.0` 00c3dd0 operator
- the three trees landed as three consecutive commits, so `v0.1.0` and `v0.2.0` each live one commit
- the plugins migration at 3816224 holds no minor, since it predates all three trees; it is `v0.0.76`
- ordering inside that burst is arbitrary and follows commit order, because the trees were authored
  together; the tags record the sequence rather than claiming a birth order

## the manifest
`plugins/*/.claude-plugin/plugin.json` carries the ERA, `MAJOR.MINOR.0`, and never the patch:

- all three read the same string, since an install takes one directory and the tree ships as a set
- a stored patch is stale the instant it is committed, because that commit moves the count
- so the patch is never written anywhere; it is derived on demand and lives in the tags alone
- that leaves nothing to sync, which is why no hook and no ci job generates a version here
- the era moves only when a plugin lands, so these three files change roughly never
- the write is a `sed` on the version line, never a `jq` render, so the rest of the file stays byte
  for byte what it was
- `.claude-plugin/marketplace.json` carries no version and never will; it names sources, not builds
- `/gitgud:audit` already walks these three manifests, so a drifted version shows up there too

## the boundary
`/gitgud:ship` is the other release skill, and the two never overlap:

- ship is portable and npm-shaped: it aborts without a `package.json`, a `production` branch, and a
  `deploy.yml`, none of which this repo has
- it is written for the host projects that install the plugins, and it stays that way
- this one is a maintainer skill for this repo only, which is why it lives under `.claude/skills/`
- nothing in `.claude/skills/` is exported, mapped, or validated by the plugin gates, so it earns no
  readme section and no `map.json` entry

## the run
- a bare run reports and writes nothing, so it is safe on any turn and answers what version this is
- `--minor` opens the next plugin era and `--major` the next major; both write and both tag
- `--repair` restates the current era into a drifted manifest, and carries no tag
- `minor vs plugin count` reports `mismatch` when a tree landed without its era being opened
- the commit, the tag and the push are emitted into the handover block and never run

## Verify
> not part of the tool; these run after a bump or before any release claim

- RUN `bash .claude/skills/bump-version/bump-version.sh` before any release claim, since the version is derived and never read from a file
- CONFIRM the drift table in chat before `--minor`, `--major` or `--repair`, since each one writes without asking
- STAGE only the three manifests; a bump commit carrying other work buries what the era change was for
- TAG only when the era changes, and retro-date it so `log --decorate` stays chronological
- PUSH the branch before the tags, since a tag pointing at an unpushed commit resolves nowhere

## Help
> IF the invocation carries `--help` or `-h`, this section is the whole turn:

```text
SKILL: /plugin:name
DESCRIPTION: <the `description` frontmatter, verbatim>
POSTURE: <the readme index's keyword for this skill>
FLAGS:
- --flag: <what it changes, in the telemetry bullet's own words>
ARGUMENTS:
- <arg>: <what it names>
ARTIFACT: <the `metadata.artifact` path, or none>
OUTPUT: <what lands in the turn: an audit entry, a handover block, an inline report>
SPEC: <this doc's own path>
```

- every field prints, in this order; one with nothing to say prints `none`
- every value is COPIED from the source named beside it, never composed fresh
- ask what they are actually trying to do, and what they have already tried
- name the flag or the sibling skill that fits their answer, then STOP
- run no step, write no file, and never fall through to step 1

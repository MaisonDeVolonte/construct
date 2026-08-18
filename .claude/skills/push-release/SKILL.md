---
name: push-release
license: MIT
compatibility: requires bash, jq, git, curl
description: bumps the four version files, then hands over the tag and the promotion (saves report to .construct/)
argument-hint: "[--help] [--check] [--patch] [--minor] [--major] [--test]"
when_to_use: "Cutting a release, promoting main to production, or answering what version this repo ships. Also when ci fails on the version files disagreeing."
metadata:
  artifact: .construct/maintainer/push-release/
---
**the version is stored, never derived:** four files say it, and one run moves all four
- `main` is the integration trunk and reaches no user, since the marketplace ref is `production`
- it reads the trunk's own ruleset, so the emitted steps branch before committing when a pr is required
- it writes the version lines and nothing else: it never commits, never merges and never pushes
- `--check` is the pure gate ci runs, so that mode reaches no network and writes no artifact

# Instructions

## the scheme
`MAJOR.MINOR.PATCH`, stored in the repo and moved by a person:

- `main` is the integration trunk and reaches no user, because the marketplace ref is `production`
- a merge to `production` is the release, and the bumped version is what fires `/plugin update`
- PATCH is the default, since most releases here are fixes to skills that already shipped
- MINOR is new work a user would notice, and MAJOR is a break in how a skill is invoked
- the commit count is no longer a version field; `git log` answers that question better

## the four files
one version said four times, and every one of them ships inside the same install:

- `plugins/operator/.claude-plugin/plugin.json`
- `plugins/gitgud/.claude-plugin/plugin.json`
- `plugins/retardify/.claude-plugin/plugin.json`
- `.claude-plugin/marketplace.json`, its own top-level field, never a per-plugin entry

`plugin.json` outranks a marketplace entry's version, so a drifted pair resolves silently to the
manifest. A value read only when it agrees is worse than an absent one, which is why no entry
carries the field. The install a user gets is one directory, so all four move together or none do.

## the branches
`production` has to stay a fast-forward of the trunk, and the sidecar refuses when it is not:

- a commit landing on `production` directly ends every later `merge --ff-only`
- a trunk rule requiring a pull request rejects the bump push, so the sidecar reads that rule first
- under that rule the bump branches before it commits, and the tag waits for the merged sha
- so the bump is authored on the trunk, before the promotion, never by a workflow reacting to it
- nothing is deployed by the push; users pull, so the promotion IS the release
- the release notes generate from the commits, which is why no CHANGELOG is written here

## the run
- `--check` is the read-only gate: the four files agree and every value parses as semver
- ci runs that flag and nothing else, since it is pure, reaches no network, and writes nothing
- a bare run means `--patch`; `--minor` and `--major` differ only in the number they compute
- the write is a `sed` on the version line, so every hand-formatted object survives it
- the commit, the tag, both pushes, the ff-merge and the release call are emitted, never run
- `trunk gate` in the telemetry says which sequence you got: `direct` or `pull request required`

## the artifact
append one entry to `[audit_file]`, in the shape under `## the entry` below:

- the heading reads `## Release Audit #[next_audit]: [timestamp]`, both taken from the telemetry
- `state` is the repo, the branches, the version move and the trunk gate, one clause each
- `files` is the FILE/WAS/NOW table the sidecar printed, as a markdown table
- `handover` is the emitted sequence, fenced as bash and copied verbatim from the terminal
- copy the handover rather than retyping it, since a retyped step is a step that can drift
- CREATE the file first if it does not exist, with `# <audit_file>` as its only line
- `--check` returns before the telemetry, so that mode names no artifact and writes none

## the entry
> the artifact this skill appends to; `/gitgud:audit` grades the shape on its next run

# .construct/maintainer/push-release/YYYY-MM-DD.md
one file per day, appended to by every bump:

- an entry captures one bump at a moment in time, so it is never edited after the fact
- lines are hyphen bullets holding a single clause, capped at 100 characters

## Release Audit #1: YYYY-MM-DD HH:MM

### state
the repo, the trunk and production branches, the release type, the version move, the trunk gate

*example:*
> - repo: owner/name, trunk: main, production: production
> - release type: patch, version: 0.12.0 -> 0.12.1
> - trunk gate: pull request required, promoting 4 commit(s)

### files
the four version files, with the value each held before and after

### handover
the emitted sequence, fenced as bash, exactly as the terminal printed it

## Verify
> not part of the tool; these run after a bump or before any release claim

- RUN `bash .claude/skills/export-readme/export-readme.sh --check` FIRST; a release ships the
  plugin copies, so a drifted one reaches users as the version that fixed nothing
- RUN `bash .claude/skills/push-release/push-release.sh --check` before claiming a version
- READ the preflight aborts rather than working around one; each names a way a release half-lands
- CONFIRM the telemetry table in chat before pasting, since the four files are already written
- STAGE only those four; a release commit carrying other work buries what the bump was for
- PASTE the handover in order, since the tag has to reach origin before the release call resolves

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

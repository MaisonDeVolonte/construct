---
name: push-release
description: "Bumps the four version files, then hands over the tag, the promotion to production and the release call."
argument-hint: "[--help] [--check] [--patch] [--minor] [--major]"
when_to_use: "Cutting a release, promoting main to production, or answering what version this repo ships. Also when ci fails on the version files disagreeing."
metadata:
  kind: spec
---
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

## Verify
> not part of the tool; these run after a bump or before any release claim

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

---
name: install
model: opus
effort: high
license: MIT
compatibility: requires bash, jq, git
description: inventory every marketplace, plugin and skill on this machine, and which wins (saves report to .construct/)
argument-hint: "[--help] [--strict] [--quick] [--test]"
disable-model-invocation: true
disallowed-tools: WebFetch, WebSearch
metadata:
  artifact: .construct/operator/install/
---

# Instructions

## Telemetry
```!
"${CLAUDE_PLUGIN_ROOT}"/skills/install/install.sh $ARGUMENTS
echo "sidecar exit: $?"
```
- `help: requested` → the run was refused before it started; `## Help` below is the whole turn
- it already ran, so there is no command to issue
- fail (`sidecar exit` > 0) with NO `--- findings ---` block → abort and report the raw terminal
  error inside a markdown code block, since the run died before it inventoried anything
- fail (`sidecar exit` > 0) with a findings block → the run graded fine and a gate tripped;
  report the errors as findings, never as a crash
- `mode: quick` → it graded and wrote NOTHING; report the six tables, the findings and the
  counts from the telemetry header, then STOP
- `mode: audit` and success (`sidecar exit` = 0) → continue to step 1

1. write the report to `.construct/operator/install/YYYY-MM-DD.md`, following `plugins/operator/skills/install/SKILL.md`
  - carry every path as the sidecar masked it, since an absolute home path is not committable
  - lead with `shadowed`, since that is the only finding a reader cannot see from a session
  - a `state` column is the sidecar's verdict; carry it across unchanged rather than regrading it
  - append; a dated report is evidence of what was true that day and is never rewritten

2. close with the two-line verdict the user actually needs:
  - every enabled name resolves to the copy its scope selected, so the install is coherent
  - OR these named plugins load a copy other than the one the reader expects, and each needs a
    `claude plugin disable` or a `claude plugin uninstall` before the intended copy wins

    a `shadowed` row means the reader is editing one copy and running another. name the command
    that frees the name; never edit a settings file to fix it, since the report is the deliverable.

## the shape
> the spec this skill writes against; the tables below are what the sidecar prints, in this order

# .construct/operator/install/YYYY-MM-DD.md
one file per day, written by `/operator:install`, appended to and never rewritten:

- gitignored with the rest of `.construct/`, and it stays that way; it names every local path
- home paths arrive already masked to `~`, and that masking is never undone in the report
- a client directory name reaching the `project` column is scrubbed before the file lands
- `verdict` leads, then `findings`, since those two are the only sections holding work
- the five inventory tables follow as evidence, in the sidecar's own order
- every state is one of: registered, orphan, loaded, shadowed, broken, tracked, untracked

## Verdict
one line: the install is coherent, or these names load a copy the reader did not intend

## Findings
| kind | subject | what it hit | resolves with |
|---|---|---|---|
| `shadowed` | `name` | an enabled install outranks the skills-dir copy | `claude plugin disable <id> -s local` |
| `orphan` | `cache` | version directories no registry row points at | `claude plugin uninstall <id>` |
| `broken_link` | `name` | a symlink under `~/.claude/skills` resolves to nothing | relink it, or remove it |
| `enabled_missing` | `id` | a scope enables a name with no install behind it | install it, or drop the entry |

## Marketplaces
the catalogue layer: what this machine trusts, and the clone each catalogue was fetched into

| name | source | repo | ref | auto |
|---|---|---|---|---|
| `TheConstruct` | github | `owner/repo` | `production` | true |

## Installs
the registry layer: one row per install, which is what a session resolves a plugin name through

| plugin | version | scope | auto | project |
|---|---|---|---|---|
| `name@marketplace` | `0.0.0` | project | false | `~/path` |

## Cache
the disk layer: every version directory, whether or not a registry row still points at it

| marketplace | plugin | version | state | size |
|---|---|---|---|---|
| `TheConstruct` | `name` | `0.0.0` | registered | `300K` |

## Skills Dir
the directory layer: a plugin loaded from `~/.claude/skills`, at user scope, in every project

| name | kind | version | state | target |
|---|---|---|---|---|
| `name` | symlink | `0.0.0` | loaded | `~/path` |

## Enabled
the consent layer: a name is claimed by whichever scope enables it, which is what shadows

| plugin | enabled | scope |
|---|---|---|
| `name@marketplace` | true | `~/.claude/settings.json` |

## Project Skills
not plugins at all: a skill this repo carries directly, which no install or scope gates

| skill | git |
|---|---|
| `name` | tracked |

## Notes
1. numbered, so `(see #1)` resolves; this is where a caveat about a layer belongs
2. name the session state the run measured, since a restart is what applies a change

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

## Subagent Style
```!
awk 'NR>1 && /^---$/ {p=1; next} p' "${CLAUDE_PLUGIN_ROOT}/subagent-styles/operator.md"
```

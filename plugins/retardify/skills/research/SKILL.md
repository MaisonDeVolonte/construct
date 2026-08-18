---
name: research
model: opus
effort: max
license: MIT
compatibility: requires bash, git
description: research a question on the web, reconcile it against this repo, then validate it (saves brief to .construct/)
argument-hint: "[--help] <text> [--test]"
disable-model-invocation: true
metadata:
  artifact: .construct/retardify/research/
---

# Instructions

## Telemetry
```!
"${CLAUDE_PLUGIN_ROOT}"/skills/research/research.sh "$ARGUMENTS"
echo "sidecar exit: $?"
```
- `help: requested` → the run was refused before it started; `## Help` below is the whole turn
- it already ran, so there is no command to issue
- fail (`sidecar exit` > 0) → abort and report the raw terminal error inside a markdown code block
- `collision: yes` → STOP and name the file already holding that slug; never overwrite a brief
- `sandbox_domains: <list>` → the hosts bash can reach; every other host needs the harness tools
- success (`sidecar exit` = 0) → take `target` from the telemetry and continue to step 1

1. probe this repo before searching anything
  - measure the local half first, so the web half has something to be reconciled against
  - read the config, run the api call, count the thing; each probe becomes one `PROBED` line
  - a question about a service probes that service live, rather than reading its docs about itself
  - a probe that cannot run here is recorded as a gap, never guessed at
  - this step is what separates a brief from a summary of somebody else's blog post

2. split the question by source tier, then fan out one agent per tier
  - `official`: the vendor's own docs for the exact thing asked about
  - `vendor`: another vendor's docs, which is how a claim gets a second independent source
  - `industry`: practitioners and analysts reporting what happened when they ran it
  - `community`: issues, forums and changelogs, which is where a documented gap gets admitted
  - 2-5 agents, briefed in the shape under `## the fan out` below, launched in one message
  - a tier with no plausible source is skipped rather than filled with a weak one

3. loop until a round stops finding sources
  - every gap a round leaves open becomes the brief for an agent in the next round
  - a round that returns no source the previous rounds missed ends the loop
  - three rounds is the cap, since a fourth has never changed a verdict and always costs
  - say how many rounds ran; `> researched ... | <n> rounds` is where that count lands

4. reconcile every surviving claim against what step 1 measured
  - each claim earns one `RECONCILED` row: what the sources say, what this repo does, the verdict
  - `agrees` means the probe and the sources match, so the claim is usable here as written
  - `conflicts` means they disagree, and the row is the finding; name which side wins in `PLAN`
  - `untested` means no probe could reach it, so it stays a claim and never becomes a fact
  - a claim that survived no verification at all is dropped, not softened

5. write `[target]` in the shape defined under `## the shape` below
  - sections in order: verdict, probed, findings, reconciled, gaps, plan, sources
  - `VERDICT` answers the question in the first section, before any evidence for it
  - every claim carries `[n]` pointing at its numbered `SOURCES` row
  - `GAPS` names what stayed open, and reads `- none` only when that was earned
  - scrub client names, tokens, and other sensitive detail before it lands in a commit

6. validate what landed, then show it and STOP
  ```bash
  plugins/retardify/skills/research/research.sh --check [target]
  ```
  - FIX every ERROR and re-run; a brief that fails its own validator is not saved work
  - report the verdict and the artifact path inline, then STOP

    NEVER act on the plan in the same turn, and never offer to; the brief IS the deliverable
    it gets read and argued with before anything in this repo changes because of it

## the fan out
> what each researching agent is told, since a vague brief returns a vague summary

- name the tier and the exact urls to start from, so two agents never fetch the same page
- name the tool: an unlisted host is unreachable from bash, so pages are fetched through the
  harness web tools instead of curl
- the sidecar's `sandbox_domains` line is what decides that, and it is read before the fan out
- ask numbered questions, since a numbered brief comes back numbered and merges mechanically
- demand a url beside every claim, and demand the fetch date with it
- demand the raw disagreement too: a doc that contradicts another doc is the finding
- close with the return shape: the agent's final text is data for this session, so no preamble
- a claim the agent could not source is returned labelled `unverified`, never dropped silently

## the shape
> the artifact this skill writes; the validator below grades what landed

**the file:** `.construct/retardify/research/YYYY-MM-DD-<title>.md`, one per brief
- `<title>` is capped at 48 characters, taken from the question the invocation carried
- one question per file; a second question is a second brief, never a second section
- lines carry a single clause, capped at 100 characters, and never wrap
- a url and a table row are exempt from the cap, since breaking either one damages it

**the content:** every claim is fetched this run, cited, and reconciled against a local probe
- `VERDICT` is the answer, and it lands before the evidence rather than after it
- `PROBED` carries measurements taken this run, each one repeatable by the reader
- `RECONCILED` is where a claim meets the probe, and every row ends in a verdict
- `SOURCES` is numbered, and every `[n]` in the brief resolves into it

# .construct/retardify/research/YYYY-MM-DD-<title>.md

# RESEARCH: the question, restated as one line
> researched YYYY-MM-DD | n sources | n probes | n rounds

## VERDICT
- the answer, before any evidence for it
- one clause per line, and no line that defers to a section below

## PROBED
- a fact this run measured in this repo, with the command or the path that produced it
- one line per measurement, and nothing here that came from a source

## FINDINGS
### topic
- a claim carrying its source as [1]
- a second claim, sourced separately, since one url is one voice [2]

## RECONCILED
| claim | the sources say | this repo | verdict |
|---|---|---|---|
| what was claimed | what they said [1] | what the probe showed | agrees |
| what was claimed | what they said [2] | what the probe showed | conflicts |
| what was claimed | what they said [3] | no probe reaches it | untested |

## GAPS
- what no source answered, each one labelled unverified
- `- none` when every question closed, and only when that was earned

## PLAN
1. verb first, runnable where a command exists, one action per line
2. name who runs each step when it is not the reader
3. a `conflicts` row from above resolves here, saying which side this repo follows

## SOURCES
1. https://example.com/a-page (official, fetched YYYY-MM-DD)
2. https://example.com/another (industry, fetched YYYY-MM-DD)
3. https://example.com/a-third (community, fetched YYYY-MM-DD)

## Verify
- RUN `plugins/retardify/skills/research/research.sh --check` once the brief is written; pass a path to scope the run
- FIX every ERROR, since each one breaks a rule this spec states outright
- STOP on a `secret` finding and ask the user before truncating it; the key needs rotating first
- JUSTIFY or fix every WARN; the sidecar tolerates them, the next reader may not
- ANSWER the checklist it prints, since those rules are the ones no script can judge

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

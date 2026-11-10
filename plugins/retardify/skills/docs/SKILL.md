---
name: docs
license: MIT
compatibility: requires bash, git
description: readme shape linter via <path> [range]: title, toc, headings, tables, notes (saves audits to .construct/)
argument-hint: "[--help] [--quick] [--strict] [--warn] <path> [range] [--test]"
when_to_use: "editing a readme or markdown doc, or when asked to review docs, formatting, or a table of contents"
paths: "**/README.md, **/readme.md, docs/**/*.md"
metadata:
  artifact: .construct/retardify/docs/
---

# Instructions

## Telemetry
```!
if [ -n "$ARGUMENTS" ];
then "${CLAUDE_PLUGIN_ROOT}"/skills/docs/docs.sh "$ARGUMENTS"; echo "sidecar exit: $?"
else echo "no target given, so nothing ran; ask what to lint: a path, a path with a line range, or pasted text"; fi
```
- `help: requested` → the run was refused before it started; `## Help` below is the whole turn
- `no target given` → ASK what to lint and STOP: a path, a `path 47:55` slice, or pasted text
- `paste: detected` → the words were prose; WRITE them to `tmp/docs-paste.md`, then run the sidecar on that path once
- this already ran; never re-issue it on the same target, since the findings above are the run
- `fail (sidecar exit > 0)` → report the raw terminal error inside a markdown code block
- `success` → take `audit_file`, then follow VERIFY below, fixing every finding
- `scope: lines N-M` → the whole doc was graded and only that slice reports; the hidden count says how much else

## Mechanics
> the falsifiable limits the sidecar grades, one label each

| label | the rule it holds |
|---|---|
| `title` `subtitle` | line 1 is the one h1, `# Name: Tagline`; line 2 is a bold one-line subtitle |
| `toc_missing` `toc_stale` `toc_missing_entry` | a fenced `TABLE OF CONTENTS` tree names every h2, and names nothing the doc lacks |
| `toc_children` `toc_order` | a row's children are the headings one level under it, in the doc's order |
| `heading_skip` `heading_gap` `heading_dup` | headings step one level at a time, sit under a blank line, and repeat no text |
| `epigraph` | an h2 or h3 opening onto content carries a one-line `> ` saying what it covers |
| `table_cols` `table_align` `table_gap` | every row carries the header's pipe count and width, under a blank line |
| `bullet_marker` `bullet_depth` | bullets are hyphens, nested two levels at most |
| `bold_inline` | bold opens a line as a `**label:**` or carries the subtitle, never a word mid-sentence |
| `paragraph` | three plain lines in a row is a paragraph; a readme reads one clause per line |
| `width` | a line caps at 120 visible characters, links measured by their text |
| `anchor_unresolved` `link_unresolved` | every `](#anchor)` lands on a heading slug, every relative link on a file |
| `note_unresolved` `note_orphan` `note_numbering` `note_shape` `notes_position` | the pointer and note pair below |
| `blank_run` `trailing` `emoji` `fence_unclosed` | one blank between blocks, no trailing space, no emoji, every fence closed |
| `secret` `scrub` | a credential-shaped string; stop and ask before touching it |

- fenced content is skipped whole, so a toc tree, a yaml block or a quoted example never trips a rule
- a `## Notes` section is graded only when present; a doc without pointers owes nothing to that rule

## Frame
> the shape a reader navigates by, top to bottom

- `# Name: Tagline` on line 1, and `**one bold line saying what it is for**` on line 2
- a fenced `TABLE OF CONTENTS` tree next, one row per h2, rows for the h3s a reader jumps to
- a row reads `├─ Label ─────── child · child`, children lowercase, the last row opening `└─`
- an h2 or h3 that carries content opens on `> one line saying what the section covers`
- a container heading opens straight onto its sub-headings and carries no epigraph
- tables are padded so every pipe lines up, and sit under one blank line
- bullets are hyphens, one clause each, two levels deep at most
- bold opens a line as a label, `**what it does:**`, and appears nowhere mid-sentence
- the human reads the body; the machine-legible detail lands under `## Notes` at the end

## Pointers
> the body stays short by pointing at a note, the way a wayfinder cites `(see #1)`

- `## Notes` is the last h2 in the doc, and holds every note as `- #N: one clause`
- notes number from 1 and climb by one; a gap or a repeat is a paste that lost count
- the body points at a note with `(see #N)`, and a pointer with no note is an ERROR
- a note nothing points at is dead weight, so it warns until a pointer lands or it is cut
- a pointer inside a code span quotes the pattern rather than using it, and is skipped

## First Principles
> what no script can judge and what the sidecar prints instead

- vibes:
  - `TITLE` the h1 names the project and the subtitle says what it is for, in one line each
  - `TOC` every row reads as the section it names, so a reader can navigate from the tree alone
  - `BREVITY` a section past a screen points at a note instead of carrying the detail inline
- NOT vibes:
  - `CONTRADICTION` a new line that disagrees with a line already in the doc is an error no script sees
  - `DRIFT` a section shaped unlike its siblings was pasted from somewhere else; reshape it to match
  - `STALE` a claim about behaviour the code no longer has; check the line against the source it names

## Verify
- RUN `plugins/retardify/skills/docs/docs.sh <path>` after writing or editing a readme; `<path> 47:55` scopes it
- FIX every ERROR, since each one breaks a rule this spec states outright
- STOP on a `secret` finding and ask the user before truncating it; the key needs rotating first
- JUSTIFY or fix every WARN; the sidecar tolerates them, the next reader may not
- ANSWER the checklist it prints, since those rules are the ones no script can judge
- READ every new claim against the lines already in the doc, since a contradiction is the finding no script sees
- APPEND the run to `audit_file` from the telemetry, in the shape below, when invoked deliberately
- SKIP that append under `--quick`, which names no audit file
- RE-RUN the sidecar after fixing, so the findings you closed are proven closed

## Artifact Template
> the artifact this skill appends to; the sidecar grades what landed on its next run

```
# .construct/retardify/docs/YYYY-MM-DD.md
one file per day, appended to by every deliberate run:

- the heading reads `## Docs Audit #[next_audit]: [timestamp]`, both taken from the telemetry
- an audit captures one doc at a moment in time, so it is never edited after the fact
- carry an unresolved finding forward by restating it, never by editing the older audit
- lines are hyphen bullets holding a single clause, capped at 100 characters
- scrub client names, tokens, and other sensitive detail before it lands in a commit

## Docs Audit #1: YYYY-MM-DD HH:MM

### state
the counts as hyphen bullets: the doc graded, its lines and headings, the scope, errors, warnings

*example:*
> - README.md graded at 2868 lines, 8 h2 and 26 h3, whole doc
> - 10 errors and 76 warnings, so ten rules the spec states outright are broken

### findings
one bullet per issue, leading with the label the sidecar printed

*example:*
> - **toc_stale** — README.md:18 names 'Hooks & Actions' where the h2 reads 'Hooks'
> - **heading_dup** — README.md:998 repeats 'Issues', so [:issues](#issues) lands on line 44
> - **table_align** — 9 rows under README.md:2252 run 13 to 97 chars wide against a 49 char header

### resolutions
one checkbox per finding, in the same order, each carrying something a reader can run

*example:*
> - [ ] `/retardify:docs README.md 1:26` after renaming the toc row to match the h2
> - [ ] `/retardify:docs README.md` once the gitgud skill heading reads 'Issues' no more
> - [ ] pad the schema table, then `plugins/retardify/skills/docs/docs.sh README.md 2250:2262`

### telemetry
the sidecar's whole output, fenced and unedited, so every claim above can be checked against it

*example:*
> ```text
> === docs.sh sidecar ===
> file: README.md
> scope: whole doc
> lines: 2868
> errors: 10
> warnings: 76
> ```

## Docs Audit #2: repeat the above format for each deliberate run on the same day
never edit an earlier audit; a stale finding is signal about how long it went unresolved
```

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

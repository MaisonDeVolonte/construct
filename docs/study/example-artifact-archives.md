# STUDY: Artifact Archives
how a trigger's output stops being chat and becomes a dated file you can diff against last week.

> committed example, kept in the repo so a fresh clone shows the shape.
> see `AGENTS/templates/study.md` for the template this follows.

- [ ] `AGENTS/templates/audits.md` is the shape the trigger must produce; write this before any code
- [ ] `AGENTS/git/gitaudit.sh` seeds the dated file and reports the target; never formats the report
- [ ] `AGENTS/git/gitaudit.md` appends the report it already wrote; reads the path, never derives it
- [ ] `.gitignore` keeps real artifacts local, so the archive never pollutes a diff
- [ ] `.claude/settings.local.json` grants the write, or every append stops for a permission prompt
- [ ] `README.md` states the append-only rule, the one thing an agent will otherwise talk itself out of
- [ ] `.github/workflows/ci.yml` fails the build if any of the above references a path that moved

## Model
sidecar seeds and measures, trigger appends, template constrains, gate verifies.
the agent is handed `file`, `time`, and `count` in telemetry so it never computes them —
every value it could get wrong is decided by the shell before it starts writing.

## Pattern
1. write the template first; it is the spec, and the trigger is graded against it
2. seed the dated file in the sidecar, echo `<type>_file`, `<type>_time`, `<type>_count`
3. anchor paths to `git rev-parse --show-toplevel` so a subdirectory run cannot scatter files
4. guard the counter with `|| true`, since `grep -c` exits 1 on no match and `set -e` will kill the run
5. add the append step to the trigger doc, keyed to that telemetry, with "never overwrite" stated
6. gitignore the artifact dir, grant the write permission, add the README section
7. exempt the artifact dir from the reference gate — it is absent from a clean checkout

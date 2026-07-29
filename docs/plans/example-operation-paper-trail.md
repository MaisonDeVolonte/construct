# AGENT PLAN: Operation Paper Trail

> committed example, kept in the repo so a fresh clone shows the shape.
> see `AGENTS/templates/plans.md` for the template this follows.

## Context
`@gitaudit`, `@gitbrutal`, and `@gitinsights` each produce a real report, print it to chat, and lose it.
logs and prompts already had dated archives; the three analysis triggers did not.
that asymmetry costs the thing those triggers are actually for — nobody can tell whether a finding
is new or the same one being regenerated weekly and skipped.

success: every analysis run lands in a dated file, and a repeat finding is visibly a repeat.

## Solution
mirror the logs/prompts shape rather than inventing a third convention:
- one file per day per type, many runs appended to the same file
- the shell sidecar seeds the dated file and reports the target back in its telemetry
- the trigger doc appends the report it already generated, as a numbered section
- the agent never derives the path or the run number; it reads both from telemetry

sidecar seeds, trigger appends. splitting it this way means a run that dies halfway
still leaves the file, and the run number can never drift from what is on disk.

## Risks
- `false authority` if an agent edits an old entry to match today's mood — archives are append-only
- `path drift` when the sidecar runs from a subdirectory, so anchor to `git rev-parse --show-toplevel`
- `set -e` kills the run when `grep -c` finds no match and exits 1; use `|| true`, never `|| echo 0`
- `clean-checkout skew` if a gate resolves paths that only exist locally as gitignored artifacts

## Checklist
- [x] write `AGENTS/templates/audits.md` as the shape the trigger must produce
- [x] seed the dated file in `gitaudit.sh` and echo `audit_file`, `audit_time`, `audit_count`
- [x] add the append step to `gitaudit.md`, keyed off that telemetry
- [x] repeat for `@gitbrutal` and `@gitinsights`
- [x] gitignore the artifact dirs, and grant write permission in host settings
- [x] document each archive in `README.md`
- [x] extend the reference scan to `.sh` and `.md`, where this repo actually lives

## Future Work
- [ ] a `@study` trigger, the one artifact type with no automation behind it
- [ ] teach `is_host_only` the difference between a missing symlink and an absent host project
- [ ] make `gitbrutal.sh` portable; it probes `src/` and `content/**`, which do not exist here
- [ ] decide whether `docs/` belongs in each host project's `.gitignore` by default

## Notes
1. the sidecar/trigger split fell out of `gh pr merge --auto` needing a *blocked* pr to queue behind
2. an already-green pr merges immediately, so auto-merge only means something with a required check
3. `grep -c` prints `0` *and* exits 1, so `|| echo 0` yields "0\n0" — cost one debugging round
4. extending the reference scan to `.sh`/`.md` produced 55 findings, 53 of them noise
5. 32 were `AGENTS.md`, a per-project symlink that cannot resolve in this repo by design
6. 18 were runtime artifact dirs, absent from any fresh clone
7. 2 were the scan matching its own source line and harvesting grep flags as paths
8. only 2 were real, which is the argument for anchoring before widening any grep

## Summary
shipped across two prs. all three analysis triggers now append to `docs/<type>/YYYY-MM-DD.md`.
the reference gate that verifies it caught two dead `@see` targets on its first real run.
the remaining gap is `@study`, which is still request-only with no trigger behind it.

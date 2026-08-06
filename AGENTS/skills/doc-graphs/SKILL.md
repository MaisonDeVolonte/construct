---
name: doc-graphs
description: Shape of a graph spec prompt file in docs/graphs/.
metadata:
  kind: spec
---
**the file:** `docs/graphs/YYYY-MM-DD-operation-<title>.md`, one per spec
- written on explicit `@graphspec --<artifact> <goal>`, where the flag defaults to `--plan`
- the flag names what executing the spec must produce, so `--plan` yields a plan file
- `--plan` is the only flag; the dated archives stay owned by their own triggers
- scrub client names, tokens, and other sensitive detail before it lands in a commit

**the form:** seven fields, each appearing exactly once, in the order below
- a key sits at column 1 and its value at column 15, so no value starts beneath its own key
- continuation lines indent to column 15 as well
- lines carry a single clause, capped at 100 characters, and never wrap
- a numbered list runs 1..n with no gap, since renumbering by hand silently drops an entry

**the content:** a spec states constraints, never plan steps
- a checkbox belongs in the artifact the spec produces, never in the spec itself
- `context` cites the repo or interrogates the user; a fact from neither does not exist
- `fan out` names 2-5 agents, then closes with one unnumbered return shape
- `rules` bind every fanned agent, and name what stays out of scope

**the pipeline:** show the saved spec and STOP; fan out begins only on the user's explicit go
- a fresh session executes the saved spec and writes whatever `output` names
- `--plan` means `docs/plans/<same-basename>.md` per `doc-plans`, and it must pass its sidecar

▸ GRAPH SPEC

GOAL:         restate the user's goal as one imperative sentence, plus what success looks like

CONTEXT:      list the facts the finished work depends on, one clause per line
              cite the repo or interrogate the user to fill gaps; never invent facts

DONE WHEN:    list the observable checks the finished work must satisfy

FAN OUT:      list the 2-5 agent types with roles and tasks assigned to each
              define one uniform return shape, unnumbered, so handoffs stay homogeneous

RULES:        list the rules every fanned agent must follow

VERIFY:       describe a fresh agent that attacks each finding against DONE WHEN and CONTEXT,
              dropping whatever fails

OUTPUT:       name the artifact executing this spec must produce, taken from the flag
              --plan means docs/plans/<same-basename>.md per doc-plans, passing its sidecar

*example:*
```
> user prompt
@graphspec --plan import the backend repo into the monorepo, keep history, near-zero downtime

> agent output
▸ GRAPH SPEC

GOAL:         import the backend repo into the frontend monorepo as an apps/api workspace,
              with history preserved and prod never down for more than a blip

CONTEXT:      1. git subtree is decided, over a fresh copy
              2. history must survive the import
              3. the frontend deploy must never fire on a backend-only commit
              4. the backend has never had an automated deploy
              5. prod runs from /var/www/html, not a checkout
              6. something unidentified also writes to /var/www/html
              7. future hosting leans digital ocean over aws, per nate
              8. facts 1-7 came from interrogating the user, not from either repo

DONE WHEN:    1. apps/api exists as a workspace in the monorepo
              2. git log inside apps/api reaches commits older than the import
              3. npm install passes from a fresh clone
              4. both builds pass from a fresh clone
              5. a green ci gate runs on apps/api/** paths
              6. one backend-only test push triggers no frontend deploy
              7. an uptime probe shows prod stayed up through the cutover

FAN OUT:      1. frontend auditor: workspace config, build wiring, every deploy trigger
              2. backend auditor: history size and shape, secrets in history, build steps
              3. import mechanic: subtree prefix layout, workspace wiring, install effects
              4. cutover planner: deploy isolation, path filters, the /var/www/html unknown
              return shape: claim, evidence as file:line or a runnable command, confidence

RULES:        1. a finding without evidence does not survive verify
              2. propose nothing that cannot land within 2-3 prs
              3. never rewrite history, the import only adds commits
              4. the repo rename stays out of scope
              5. the backend deploy mechanism itself stays out of scope

VERIFY:       a fresh agent attacks each finding against DONE WHEN and CONTEXT
              evidence that fails to reproduce, or contradicts a known fact, kills the finding

OUTPUT:       docs/plans/2026-07-30-operation-monorepo.md, per doc-plans, passing its sidecar

```

```
VERIFY - not part of the artifact
- RUN `AGENTS/skills/doc-graphs/doc-graphs.sh` once the spec is written; pass a path to scope the run
- FIX every ERROR, since each one breaks a rule this spec states outright
- STOP on a `secret` finding and ask the user before truncating it; the key needs rotating first
- JUSTIFY or fix every WARN; the sidecar tolerates them, the next reader may not
- ANSWER the checklist it prints, since those rules are the ones no script can judge
```

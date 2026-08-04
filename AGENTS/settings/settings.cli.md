# --settings (the cli scope)
> no file to copy — this scope is a flag, and nothing in it survives the session. mechanics live
> in [README.md](../../README.md), this file covers what the flag reaches and how to drive it

the only scope with nothing on disk. it exists to answer one question before you commit an answer
to a scope someone inherits: does this rule do what i think it does? every other file here is a
floor with a reader, and this is the one you are allowed to be wrong in.

## what it takes

`--settings <path>` or `--settings '<inline json>'`
- a settings file path, or a json string, up to 2 MiB
- keys you set override the same keys below; keys you omit keep their file values
- nothing is written anywhere, so quitting reverts all of it

## where it sits

`managed → cli → local → project → user`
- second only to managed, so it outranks all three files on disk
- managed still wins, so a frozen machine cannot be tested around, only tested against
- arrays merge rather than replace, so a deny in any scope still bites here

## what this scope reaches and project and local do not
> read from user, cli and managed only, ignored in the two committed scopes

- `autoMode`
- `footerLinksRegexes`
- `sandbox.credentials` mask entries, which is why a mask is testable here and not in a repo

the split is trust rather than specificity: project and local files travel in a clone, so letting
them mask a credential would let a repo decide what happens to your tokens.

## cheat sheet

| goal                                   | command                                                    |
|----------------------------------------|------------------------------------------------------------|
| try one rule, save nothing             | `claude --settings '{"permissions":{"deny":["Bash(rm *)"]}}'` |
| try a whole candidate file             | `claude --settings ./try.json`                             |
| load only some scopes                  | `claude --setting-sources user,project`                    |
| disable every customization            | `claude --safe-mode`                                       |
| skip hooks, skills, plugins, mcp, md   | `claude --bare`                                            |
| print installation and settings state  | `claude doctor`                                            |
| grant one tool for one session         | `claude --allowedTools "Bash(git status)"`                 |
| deny one tool for one session          | `claude --disallowedTools "Bash(git push *)"`              |
| start in a permission mode             | `claude --permission-mode plan`                            |
| add a second working directory         | `claude --add-dir ../other-repo`                           |
| trace why a call was allowed or denied | `claude --debug`                                           |

`--setting-sources` takes `user`, `project` and `local` only, so managed always loads. that makes
it the way to reproduce a stranger's floor: drop `local`, drop `project`, and see what is left.

## how to use it here

1. write the rule inline and open a session with it
2. run the thing it should stop, and confirm the refusal reads the way you expect
3. run the thing it should still allow, since a rule that blocks everything also passes step 2
4. promote it to whichever scope question it answers, then rerun `@settingsaudit`

testing at cli and then pasting into a file is the only order that keeps a broken rule out of a
committed scope. a `//` comment voids a whole settings file in silence, and this is where that
costs one session instead of every clone.

## caveats

- a rule that works here can still fail once installed, since cli outranks local and project
- the sandbox is enabled at every scope, so a cli session is not an unsandboxed session
- the published cli reference omits managed from its precedence list and names project settings
  `.claude/project-settings.json`; the settings page and this repo both disagree with it

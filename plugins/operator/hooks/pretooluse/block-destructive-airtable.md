---
name: block-destructive-airtable
description: denies airtable requests that update or delete before bash runs them, so the agent can only read and create
---

**reads and creates pass; updates and deletes go back to the user:** the whole string is checked
- depends on no sibling plugin; one self-contained file plus `jq`
- decides one thing: does a string naming airtable carry DELETE, PUT or PATCH, or a flag that hides the method
- `-T` implies PUT; `-K`, `--variable`, `--expand-*`, a `$`-method and a method-override header hide it, so each one is denied
- a method flag passes only as a plain GET, POST or HEAD, so a quote-split `-X D"ELETE"` is denied
- inline code is read too: `.delete(`, `method: 'PATCH'` and `request('PUT'` are each denied
- PATCH is denied too: a rename loses no data, but it breaks every script that reads fields by name
- `/sync/` is the one destructive POST: the sync api replaces a synced table's rows
- a host built from a variable passes unseen, and a script's own requests never reach this check
- the pat's scopes are the real limit: no records write, and the rest api has no table or field delete
- costs one process spawn per Bash call, plus one grep for strings that don't name airtable

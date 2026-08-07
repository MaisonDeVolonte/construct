#!/bin/bash
# ==========================================================
# @file secrets.sh - credential scan shared by every sidecar
# ==========================================================
# @description
# - sourced, never run; every sidecar in this plugin reads its credential patterns from here
# - one copy per plugin, since an install copies a plugin's own directory and never a sibling
# - the copies are byte-identical by contract, and `/gitgud:audit` reports the moment one drifts
# - `scan_secrets <file>` reports every match through the caller's own `err` and `warn`
# - CONTRACT: the caller defines `err SEV file line category detail` and `warn` the same way
# - an unambiguous provider token is an ERROR, so the run stops and a human decides what happens
# - a merely credential-shaped string is a WARN, since most of them here are commit shas
# - a suspect value opening with `$` or a backtick is skipped, since a literal credential never does
# - without that, every `token=${VAR}` a sidecar declares would warn on every run forever
# - edit this copy only; `tools/sync-secrets/sync-secrets.sh --write` propagates it to the siblings
# @see tools/sync-secrets/sync-secrets.sh, plugins/gitgud/skills/audit/audit.sh, .github/workflows/ci.yml

# sourcing is the only supported use: run directly and it would define functions into a shell that
# exits immediately afterwards, which looks like it worked and does nothing
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  echo "fatal: source this file from a sidecar, do not run it" >&2; exit 1
fi

# unambiguous credentials: a provider prefix, a private key block, or a url carrying its own
# password — these stop the run, because a key that reaches a commit cannot be un-leaked
SECRET_PATTERNS='AKIA[0-9A-Z]{16}|ASIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|glpat-[A-Za-z0-9_-]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}|sk-[A-Za-z0-9]{20,}|[sr]k_(live|test)_[A-Za-z0-9]{20,}|AIza[0-9A-Za-z_-]{35}|ya29\.[A-Za-z0-9_-]{20,}|npm_[A-Za-z0-9]{36}|eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|[a-z][a-z0-9+.-]*://[^/[:space:]:@]+:[^/[:space:]@]+@'

# shapes that are a commit sha or a digest nine times out of ten here, and a secret the tenth,
# so they only ever warn; matched case-insensitively, since a sha reads the same in either case
SUSPECT_PATTERNS='[0-9a-f]{32,}|(api[_-]?key|secret|token|password|passwd|credential)[[:space:]]*[:=][[:space:]]*[^$`[:space:]][^[:space:]]{7,}'

# a finding names what it matched, so it truncates first: this report gets pasted into logs and prs
preview() {
  local token=$1
  if [ -z "$token" ]; then printf 'credential-shaped string'
  elif [ ${#token} -le 8 ]; then printf '%s' "$token"
  else printf '%s… (%s chars)' "${token:0:6}" "${#token}"; fi
}

# "scrub client names, tokens, and other sensitive detail before it lands in a commit", split by
# how sure the match is: the caller decides nothing, it only supplies where findings go
scan_secrets() {
  local file=$1 hit line token
  # a missing contract is a silent no-op otherwise, and a scan that reports nothing reads as clean
  if ! command -v err >/dev/null 2>&1 || ! command -v warn >/dev/null 2>&1; then
    echo "fatal: scan_secrets needs err() and warn() from the calling sidecar" >&2; return 1
  fi
  while IFS= read -r hit; do
    if [ -z "$hit" ]; then continue; fi
    line=${hit%%:*}
    token=$(printf '%s' "${hit#*:}" | grep -oE "$SECRET_PATTERNS" | head -n 1 || true)
    err "$file" "$line" secret "$(preview "$token"); STOP and ask the user before truncating it"
  done < <(grep -nE "$SECRET_PATTERNS" "$file" || true)
  while IFS= read -r hit; do
    if [ -z "$hit" ]; then continue; fi
    line=${hit%%:*}
    token=$(printf '%s' "${hit#*:}" | grep -oiE "$SUSPECT_PATTERNS" | head -n 1 || true)
    warn "$file" "$line" scrub "$(preview "$token"); confirm it is safe to commit"
  done < <(grep -niE "$SUSPECT_PATTERNS" "$file" || true)
}

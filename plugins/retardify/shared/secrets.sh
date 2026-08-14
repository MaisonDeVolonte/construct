#!/bin/bash
# ==========================================================
# @file secrets.sh - credential scan shared by every sidecar
# ==========================================================
# @description
# CONTRACT
# - sourced, never run; the caller defines `err SEV file line category detail` and `warn` alike
# - `scan_secrets <file>` grades every match and reports through those two, deciding nothing itself
# - an unambiguous provider token is an ERROR; a merely credential-shaped string is a WARN
# COPIES
# - one per CALLING plugin, since an install copies a plugin's own directory and never a sibling
# - operator and retardify both call `scan_secrets`; gitgud never did, so it carries no copy
# - byte-identical by contract, hand-edited in both places, never generated from anywhere
# - `/gitgud:audit` md5s every copy it finds and is the ONLY thing comparing them
# @see plugins/gitgud/skills/audit/audit.sh, plugins/operator/shared/secrets.sh, plugins/retardify/shared/secrets.sh

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  echo "fatal: source this file from a sidecar, do not run it" >&2; exit 1
fi

# unambiguous credentials: a provider prefix, a private key block, or a url carrying its own
# password — these stop the run, because a key that reaches a commit cannot be un-leaked
SECRET_PATTERNS='AKIA[0-9A-Z]{16}|ASIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|glpat-[A-Za-z0-9_-]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}|sk-[A-Za-z0-9]{20,}|[sr]k_(live|test)_[A-Za-z0-9]{20,}|AIza[0-9A-Za-z_-]{35}|ya29\.[A-Za-z0-9_-]{20,}|npm_[A-Za-z0-9]{36}|eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|[a-z][a-z0-9+.-]*://[^/[:space:]:@]+:[^/[:space:]@]+@'

# shapes that are a commit sha or a digest nine times out of ten here, and a secret the tenth,
# so they only ever warn; a value opening with `$` or a backtick is a variable and never matches
SUSPECT_PATTERNS='[0-9a-f]{32,}|(api[_-]?key|secret|token|password|passwd|credential)[[:space:]]*[:=][[:space:]]*[^$`[:space:]][^[:space:]]{7,}'

# a finding names what it matched, so it truncates first: this report gets pasted into logs and prs
preview() {
  local token=$1
  if [ -z "$token" ]; then printf 'credential-shaped string'
  elif [ ${#token} -le 8 ]; then printf '%s' "$token"
  else printf '%s… (%s chars)' "${token:0:6}" "${#token}"; fi
}

# both severities walk a file the same way, so the pattern set, the grep flags and the sink are
# arguments; `-n"$flags"` stays quoted, since splitting the flags would drop the line numbers
report_matches() {
  local file=$1 patterns=$2 flags=$3 sink=$4 category=$5 advice=$6 hit line token
  while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    line=${hit%%:*}
    token=$(printf '%s' "${hit#*:}" | grep -o"$flags" "$patterns" | head -n 1 || true)
    "$sink" "$file" "$line" "$category" "$(preview "$token"); $advice"
  done < <(grep -n"$flags" "$patterns" "$file" || true)
}

scan_secrets() {
  local file=$1
  # a missing contract is a silent no-op otherwise, and a scan reporting nothing reads as clean
  if ! command -v err >/dev/null 2>&1 || ! command -v warn >/dev/null 2>&1; then
    echo "fatal: scan_secrets needs err() and warn() from the calling sidecar" >&2; return 1
  fi
  report_matches "$file" "$SECRET_PATTERNS" E err secret \
    "STOP and ask the user before truncating it"
  report_matches "$file" "$SUSPECT_PATTERNS" iE warn scrub \
    "confirm it is safe to commit"
}

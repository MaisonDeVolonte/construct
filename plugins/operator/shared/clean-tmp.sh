#!/bin/bash
# ========================================================================
# @file clean-tmp.sh - sweeps every repo-local tmp/ artifact under one tag
# ========================================================================
# @description
# - every plugins/*/skills/*/*.sh sidecar's cleanup() trap calls this with its own tag
# - one shared sweep means a retention-policy change is a one-file edit, not eighteen
# @see plugins/operator/skills/*/*.sh

TAG="${1:?clean-tmp.sh: missing tag argument}"
case "$TAG" in
  */*|.|..|"") echo "clean-tmp.sh: refusing unsafe tag '$TAG'" >&2; exit 1 ;;
esac

TMPROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)/tmp"
rm -rf "$TMPROOT/$TAG"-*

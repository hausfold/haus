#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: $0 [--quiet] BEFORE.json AFTER.json" >&2
  exit 2
}

quiet=false
if [[ ${1:-} == --quiet ]]; then
  quiet=true
  shift
fi
[[ $# -eq 2 ]] || usage

before=$1
after=$2

if cmp -s "$before" "$after"; then
  echo "desktop projections are equal"
  exit 0
fi

if $quiet; then
  echo "desktop projections differ" >&2
else
  diff -u "$before" "$after" >&2 || true
fi
exit 1

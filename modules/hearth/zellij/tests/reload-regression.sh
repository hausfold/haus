#!/bin/bash
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
reload="${here}/../reload.sh"
fixture="${here}/foreground-child"
fake="${here}/fake-zellij.sh"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/zreload-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/good/main" "$tmp/bad/main"
cp "$fixture/generation" "$fixture/claude-panes.tsv" "$tmp/good/main/"
cp "$fixture/generation" "$tmp/bad/main/"

run_print() {
    local root="$1"
    ZELLIJ_SESSION_NAME=main \
    ZRELOAD_STATE_ROOT="$root" \
    ZRELOAD_PANE_MAP_ROOT="$tmp/no-reports" \
    ZRELOAD_ZELLIJ_BIN="$fake" \
    ZRELOAD_TEST_PANES="$fixture/panes.json" \
    ZRELOAD_TEST_LAYOUT="$fixture/layout.kdl" \
        bash "$reload" --print
}

run_print "$tmp/good" >"$tmp/layout.kdl"
zellij setup --dump-layout "$tmp/layout.kdl" >/dev/null

[ "$(grep -c 'args \"--resume\"' "$tmp/layout.kdl")" -eq 3 ]
! grep -q 'sourcekit-lsp' "$tmp/layout.kdl"
grep -q 'pane cwd=\"code/workshop\"' "$tmp/layout.kdl"

if run_print "$tmp/bad" >"$tmp/unsafe.out" 2>"$tmp/unsafe.err"; then
    printf 'expected an ambiguous foreground child to abort\n' >&2
    exit 1
fi
grep -q 'cannot prove every command pane is resumable' "$tmp/unsafe.err"

printf 'zreload regression tests passed\n'

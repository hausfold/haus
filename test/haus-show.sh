#!/usr/bin/env bash
# `haus show`'s own suite — the half the `desktop-show` flake check cannot run.
#
# That check pins the READING (class, counts, which room each leaf files under)
# and it is pure lib, so it runs inside a Nix build. Everything this command
# actually IS lives outside one: the script shells out to `nix eval`, which no
# derivation may do, and its whole contract with a publisher's CI is an EXIT
# CODE. So the exit codes, the flags and the JSON envelope are pinned here, run
# from CI's eval job, where a real nix exists.
#
# Runs on Linux: nothing about the desktop rules is a Mac, and a publisher's
# runner isn't one either — which is the case this command exists to serve.
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"

# The built wrapper, which is what `nix run …#show` gives a stranger. Overridable
# so a local run can point at a copy it already built and skip the ~10s.
if [ -z "${HAUS_SHOW_BIN:-}" ]; then
  HAUS_SHOW_BIN="$(nix build --no-link --print-out-paths "$repo#show")/bin/haus-show"
fi
show="$HAUS_SHOW_BIN"
[ -x "$show" ] || { printf 'FAIL: no haus-show at %s\n' "$show" >&2; exit 1; }

fixtures="$repo/test/desktops"
tmp="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$tmp"' EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

# Run it and capture all three: stdout, stderr and the status. `set +e` around
# the call only — the status IS the assertion here, so it must never be the
# thing that aborts the suite.
out="" err="" status=0
run() {
  set +e
  out="$("$show" "$@" 2>"$tmp/err")"
  status=$?
  set -e
  err="$(cat "$tmp/err")"
}

expect_status() { [ "$status" = "$1" ] || fail "$2: expected exit $1, got $status"; }
has()   { printf '%s\n' "$out" | grep -qF -- "$1" || fail "$2: expected to find '$1'"; }
lacks() { printf '%s\n' "$out" | grep -qF -- "$1" && fail "$2: expected NOT to find '$1'"; return 0; }

# ---- 0: a valid desktop passes, and says what it sets -------------------------
run "$fixtures/valid-sample.nix"
expect_status 0 "valid desktop"
has "a desktop — data only" "valid desktop"
has "9 options across 6 rooms" "valid desktop"
has "haus.terminal.editorName" "valid desktop"
# Filed under the ROOM a person meets, not the namespace they type. This is the
# one thing the report adds over `checkDesktop` printing `true`.
has "Development" "valid desktop"
has "Shared surfaces" "valid desktop"
# And what stays theirs.
has "Apps · Appearance" "valid desktop"

# ---- 1: a desktop that breaks a rule fails, naming every rule -----------------
run "$fixtures/host-only-secret.nix"
expect_status 1 "host-only desktop"
has "not a desktop" "host-only desktop"
has "2 rules broken" "host-only desktop"
has "haus.secrets.provider is host-only" "host-only desktop"
# The checker prefixes every diagnostic with the file it came from, which is
# right inside a flake check over a directory and noise in a one-file report.
lacks "$fixtures/host-only-secret.nix: haus" "host-only desktop"

# One rule, so the count is not silently plural.
run "$fixtures/unknown-option.nix"
expect_status 1 "unknown option"
has "1 rule broken" "unknown option"

# ---- 3: code, unclaimed — the asymmetry ---------------------------------------
# A module function is reported as code without being asked, because guessing
# "this is code" can only ever be over-cautious. It is NOT a pass: a publisher's
# CI must go red the day their desktop file becomes a function.
run "$fixtures/function.nix"
expect_status 3 "unclaimed room"
has "this is CODE" "unclaimed room"
has "run activation scripts as root" "unclaimed room"
lacks "✓" "unclaimed room"

# Claimed, it is the answer you asked for.
run --room "$fixtures/function.nix"
expect_status 0 "claimed room"
has "this is CODE" "claimed room"

# --room on a DATA file is still a room: a desktop-shaped attrset is a perfectly
# good module, so the flag is a statement about how the file will arrive, and
# nothing is checked when it is given. Never the other way round — no content
# makes haus call something data.
run --room "$fixtures/valid-sample.nix"
expect_status 0 "data claimed as room"
has "this is CODE" "data claimed as room"
lacks "every leaf it sets" "data claimed as room"

# ---- 2: the arguments, and the file ------------------------------------------
run "$tmp/nope.nix"
expect_status 2 "missing file"
printf '%s\n' "$err" | grep -qF "no such file" || fail "missing file: reason not on stderr"

run "$fixtures"
expect_status 2 "a directory"

run --nonsense "$fixtures/valid-sample.nix"
expect_status 2 "unknown flag"

run
expect_status 2 "no argument"

# A file that is not Nix at all.
printf 'this is not nix {{{\n' >"$tmp/broken.nix"
run "$tmp/broken.nix"
expect_status 2 "unparseable"

# A file that parses and then throws. `tryEval` catches this one; a TYPE error
# it would not, which is why the reader tests a value's type before touching it.
printf '{ haus.ui.scale = throw "boom"; }\n' >"$tmp/throws.nix"
run "$tmp/throws.nix"
expect_status 2 "throwing value"

# ---- --json -------------------------------------------------------------------
run --json "$fixtures/valid-sample.nix"
expect_status 0 "json valid"
printf '%s' "$out" | jq -e '
  .schemaVersion == 1
  and .class == "desktop"
  and .checked == true
  and .ok == true
  and (.sets | length) == 9
  and (.rooms | map(.room)) == ["displays","development","bar","launcher","focus","haus"]
  and (.silent | length) == 7
' >/dev/null || fail "json valid: envelope is not the documented shape"
# Data on stdout, diagnostics on stderr, and NO human rendering mixed in.
lacks "🌫" "json valid"
[ -z "$err" ] || fail "json valid: stderr should be empty, got '$err'"

run --json "$fixtures/unknown-option.nix"
expect_status 1 "json failing"
printf '%s' "$out" | jq -e '.ok == false and (.failures | length) == 1' >/dev/null \
  || fail "json failing: failures not reported"

# `checked` is said out loud rather than inferred from an empty failure list,
# because a room and a clean desktop otherwise look identical in JSON — which is
# the one confusion this command must never cause.
run --json --room "$fixtures/function.nix"
expect_status 0 "json room"
printf '%s' "$out" | jq -e '.class == "room" and .checked == false and .ok == true' >/dev/null \
  || fail "json room: a room must not read as a checked pass"

# ---- it really does write nothing --------------------------------------------
# `cksum` rather than md5sum/md5, whose names differ by platform — and content,
# not just the file list, because the failure worth catching is a checker that
# rewrites what it read.
snapshot() { find "$fixtures" -type f -exec cksum {} + | sort; }
before="$(snapshot)"
run "$fixtures/valid-sample.nix"
after="$(snapshot)"
[ "$before" = "$after" ] || fail "show changed the directory it read"

# ---- --help --------------------------------------------------------------------
run --help
expect_status 0 "help"
has "exit codes" "help"
has "never infers that something is safe" "help"

printf 'ok — haus show: %s\n' "$show"

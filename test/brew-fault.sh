#!/usr/bin/env bash
# What `haus` can see about a cask that did NOT install.
#
# The regression suite for the half of the AeroSpace tap S1 that was not the
# tap. `brew bundle` is the last activation step before home-manager, so when
# it failed the machine lost its entire user half — and `haus doctor` said
# nothing at all, because the only cask arm it had ran the other way (installed
# but undeclared). Activation now CATCHES that failure and carries on
# (modules/core/default.nix), which makes noticing the whole job of this pair:
# `missing_casks` says which app is absent, and `haus rebuild` fails on the
# marker so the exit code still means something.
#
# Everything exercised here is pure list arithmetic over two text sources — a
# Brewfile and `brew list --cask` — so it runs on LINUX in CI even though a real
# `haus doctor` needs a Mac with a built system. `brew` is a stub on PATH and
# `declared_brewfile` is redefined after the source, which is what keeps the
# suite hermetic: neither /run/current-system nor a real Homebrew is touched.
set -euo pipefail

# ── an interpreter that can actually run haus.sh ─────────────────────────────
# The same block as test/haus-plan.sh, test/haus-settings.sh and
# test/haus-add.sh, and for the same reason: haus.sh is written for bash 4+ and
# /bin/bash 3.2 MIS-PARSES it rather than degrading — `coproc` is no keyword
# there, so snug_open's closing `}` ends the function early and its body runs at
# load time. This suite sources haus.sh as a library, so this process is the
# subject's interpreter. Copies rather than a sourced helper, the size call
# AGENTS.md makes for the Ghostty pre-warm; test/phase-painter.bats pins the
# invariant so a suite cannot opt out of it quietly.
if [ "${BASH_VERSINFO[0]:-0}" -lt 4 ]; then
  for _bash in /run/current-system/sw/bin/bash /opt/homebrew/bin/bash \
               "$(command -v bash || true)" /bin/bash; do
    [ -n "$_bash" ] && [ -x "$_bash" ] || continue
    [ "$("$_bash" -c 'echo ${BASH_VERSINFO[0]}' 2>/dev/null || echo 0)" -ge 4 ] || continue
    # shellcheck disable=SC2093
    exec "$_bash" "$0" "$@"
  done
  printf 'FAIL: haus.sh needs bash 4+ and this is %s — no newer one found\n' \
    "${BASH_VERSION:-?}" >&2
  exit 1
fi

repo="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$tmp"' EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
eq() { [ "$1" = "$2" ] || fail "$3 — expected [$2], got [$1]"; }

# ── the stub Homebrew ────────────────────────────────────────────────────────
# `brew list --cask` is the only call either function makes. INSTALLED is read
# at call time, so a case can move the machine's state between assertions.
mkdir -p "$tmp/bin"
cat >"$tmp/bin/brew" <<'STUB'
#!/usr/bin/env bash
case "$*" in
  "list --cask") printf '%s\n' $INSTALLED ;;
  *) exit 1 ;;
esac
STUB
chmod +x "$tmp/bin/brew"
# haus.sh rebuilds PATH at load and puts `$HAUS_BREW_PREFIX/bin` on it, so a
# stub merely PREPENDED here would lose to the machine's real Homebrew on a Mac.
# Pointing the prefix at the fixture is both the fix and a free assertion that
# the variable is honoured — `$tmp/bin/brew` is exactly the `<prefix>/bin/brew`
# shape the real one has.
export HAUS_BREW_PREFIX="$tmp"
PATH="$tmp/bin:$PATH"; export PATH

mkdir -p "$tmp/consumer"
printf '{ }\n' >"$tmp/consumer/flake.nix"
export HAUS_CONSUMER="$tmp/consumer" HAUS_LIB=1
# shellcheck disable=SC1090,SC1091
source "$repo/modules/core/haus.sh"
REPORT=1

# The one thing that would otherwise reach outside the sandbox: the real
# function reads the RUNNING system's activate script for the path it fed
# `brew bundle`. Redefined rather than parameterised — the subject should keep
# reading the built artifact, and a knob added only for a test is a second way
# to be wrong.
# NOT named `brewfile`: `missing_casks` declares `local brewfile` before it
# calls this, and bash's scoping is dynamic — the callee would see the caller's
# empty local and die under `set -u`. Which is the bug this suite found on its
# own first run.
fixture_brewfile="$tmp/Brewfile"
declared_brewfile() { printf '%s\n' "$fixture_brewfile"; }

# ── 1. a declared cask that is not installed is NAMED ────────────────────────
cat >"$fixture_brewfile" <<'EOF'
tap "nikitabobko/tap", trusted: true
cask "ghostty", trusted: true
cask "aerospace", trusted: true
cask "zed", trusted: true
EOF
INSTALLED="ghostty zed"; export INSTALLED
eq "$(missing_casks | paste -sd, -)" "aerospace" "the refused cask is the one reported"

# ── 2. all of them absent, in Brewfile order-independent sorted form ─────────
INSTALLED=""
eq "$(missing_casks | paste -sd, -)" "aerospace,ghostty,zed" "every declared cask is missing when none is installed"

# ── 3. nothing missing draws nothing ─────────────────────────────────────────
# `grep .` makes the function exit 1 on an empty result, so the `|| true` in it
# is what keeps a caller under `set -e` alive. A green machine reaching this
# suite's own `set -e` is the assertion.
INSTALLED="ghostty aerospace zed"
eq "$(missing_casks | paste -sd, -)" "" "a machine with every declared cask says nothing"

# ── 4. a fully-qualified cask is not missing under its bare name ─────────────
# `brew list --cask` prints `aerospace`, never `nikitabobko/tap/aerospace`, so
# without the prefix strip a fully-qualified declaration reads as absent on
# every rebuild, forever — a permanent red line about an app that is installed.
cat >"$fixture_brewfile" <<'EOF'
cask "nikitabobko/tap/aerospace", trusted: true
cask "ghostty", trusted: true
EOF
INSTALLED="aerospace ghostty"
eq "$(missing_casks | paste -sd, -)" "" "a tap-qualified declaration matches the bare installed name"

# ── 5. an undeclared cask is NOT a missing one ───────────────────────────────
# The pre-existing arm's direction, asserted here so the two can never be
# confused: something installed that nothing declares is drift, not a failure.
INSTALLED="aerospace ghostty slack"
eq "$(missing_casks | paste -sd, -)" "" "an extra cask on the machine is not a missing declaration"

# ── 6. no Brewfile at all is silence, not an error ───────────────────────────
# The state of a machine that has never activated. Under `set -e` a non-zero
# return here would kill `haus doctor` outright, which is the class of bug that
# made doctor stop at the "Secrets" header.
rm -f "$fixture_brewfile"
eq "$(missing_casks | paste -sd, -)" "" "no Brewfile is silence"
missing_casks >/dev/null || fail "missing_casks returned non-zero with no Brewfile — that aborts doctor"

# ── 7. no brew at all is silence too ─────────────────────────────────────────
rm -f "$tmp/bin/brew"
eq "$(missing_casks | paste -sd, -)" "" "no Homebrew is silence"
missing_casks >/dev/null || fail "missing_casks returned non-zero with no brew"

printf 'ok — brew-fault (7 cases)\n'

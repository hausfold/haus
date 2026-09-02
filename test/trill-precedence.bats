#!/usr/bin/env bats
# Hermetic tests for modules/core/trill.sh — WHICH Trill.app the name on PATH
# resolves to.
#
# Why a suite for four lines of `for`. This is a precedence with no error
# surface: every candidate is a real, signed, working Trill, so picking the
# wrong one costs nothing at the call site and everything downstream. A build
# left in ~/Applications by trill's own `scripts/dev-install.sh` used to outrank
# the bundle `haus.notifications.compositor` pins at /Applications, on every
# rebuild, forever — the room rewrites its own path and can never displace the
# copy in front of it, so a Mac goes on calling a months-old daemon and nothing
# says a word. Measured on mbp 2026-09-02: the stray hung `trill history` at
# exactly 8192 bytes, the unix socket's send buffer, while the pinned bundle
# beside it answered fine.
#
# So the order is asserted three ways: behaviourally on the wrapper itself, on
# the "home still works when it is the only one" claim the order rests on, and
# then once per FILE that spells the list out — the wrapper, haus.sh's
# `trill_bin`, the bar's trill pill. Those last three read each file on its own
# rather than diffing them against each other, which is deliberate: the three
# lists are written in three different shells' idioms (`${HOME:-}`, `$HOME`, a
# Go-free `for`), so there is no common string to diff, and what has to hold is
# a property each file can be asked about alone.
#
# Hermetic: fake bundles under $BATS_TEST_TMPDIR, and the subject's one absolute
# path rewritten to point inside it. Needs only bash + bats — no Mac, no Trill.

bats_require_minimum_version 1.5.0

REPO="${BATS_TEST_DIRNAME}/.."
WRAPPER="$REPO/modules/core/trill.sh"

setup() {
  TMP="$BATS_TEST_TMPDIR"
  export HOME="$TMP/home"
  mkdir -p "$HOME"

  # Stands in for the real /Applications. The subject is a COPY with the two
  # absolute paths repointed inside the sandbox — the literals change, the ORDER
  # (which is what every case below is about) does not.
  SYSAPPS="$TMP/system/Applications"

  # The second rewrite is `${HOME:-}`'s DEFAULT, not the variable: with HOME
  # unset the real candidate collapses to the literal `/Applications/Trill.app`,
  # so on a Mac that actually has one the unset-HOME case would exec it. Giving
  # the guard a sandbox default keeps that case honest on any machine, and keeps
  # the guard itself under test — drop the `:-` and this sed stops matching,
  # which the assertion below turns red.
  SUBJECT="$TMP/trill"
  sed -e "s#\"/Applications/Trill.app\"#\"$SYSAPPS/Trill.app\"#" \
      -e "s#\"\${HOME:-}/Applications/Trill.app\"#\"\${HOME:-$TMP/nohome}/Applications/Trill.app\"#" \
      "$WRAPPER" >"$SUBJECT"
  chmod +x "$SUBJECT"

  # If either substitution silently misses, cases below would pass by testing a
  # wrapper with no candidate there at all.
  grep -q "\"$SYSAPPS/Trill.app\"" "$SUBJECT"
  grep -q "\${HOME:-$TMP/nohome}/Applications/Trill.app" "$SUBJECT"

  export TRILL_LOG="$TMP/calls.log"
}

# A bundle whose executable names itself, echoes its argv and exits with a code
# it was told — enough to answer "which one answered", "did argv survive" and
# "did the exit code survive" in one recorder.
make_bundle() {
  local root="$1" marker="$2"
  mkdir -p "$root/Contents/MacOS"
  cat >"$root/Contents/MacOS/Trill" <<EOF
#!/usr/bin/env bash
printf '%s %s\n' "$marker" "\$*" >>"\$TRILL_LOG"
exit "\${TRILL_FAKE_EXIT:-0}"
EOF
  chmod +x "$root/Contents/MacOS/Trill"
}

answered() { head -n1 "$TRILL_LOG" | cut -d' ' -f1; }

# --- the order ---------------------------------------------------------------

@test "the pinned /Applications bundle beats a dev build in ~/Applications" {
  make_bundle "$SYSAPPS/Trill.app" system
  make_bundle "$HOME/Applications/Trill.app" home

  run env -u TRILL_APP sh "$SUBJECT" doctor
  [ "$status" -eq 0 ]
  [ "$(answered)" = system ]
}

@test "\$TRILL_APP still beats both, so a branch build is one variable away" {
  make_bundle "$SYSAPPS/Trill.app" system
  make_bundle "$HOME/Applications/Trill.app" home
  make_bundle "$TMP/branch/Trill.app" branch

  run env TRILL_APP="$TMP/branch/Trill.app" sh "$SUBJECT" doctor
  [ "$status" -eq 0 ]
  [ "$(answered)" = branch ]
}

@test "~/Applications is a fallback, not a demotion: alone, it still answers" {
  make_bundle "$HOME/Applications/Trill.app" home

  run env -u TRILL_APP sh "$SUBJECT" doctor
  [ "$status" -eq 0 ]
  [ "$(answered)" = home ]
}

@test "a \$TRILL_APP pointing at nothing falls through rather than failing" {
  make_bundle "$SYSAPPS/Trill.app" system

  run env TRILL_APP="$TMP/gone/Trill.app" sh "$SUBJECT" doctor
  [ "$status" -eq 0 ]
  [ "$(answered)" = system ]
}

# --- what the wrapper must not have grown ------------------------------------

@test "argv and exit code come back untouched — the wrapper holds no opinion" {
  make_bundle "$SYSAPPS/Trill.app" system

  run env -u TRILL_APP TRILL_FAKE_EXIT=5 sh "$SUBJECT" ask --pill Yes --pill No
  [ "$status" -eq 5 ]
  [ "$(cat "$TRILL_LOG")" = "system ask --pill Yes --pill No" ]
}

@test "no bundle anywhere: 127, and the message names both directories" {
  # `run -127` rather than a bare `run`: 127 is the expected answer here, and
  # bats warns (BW01) about an unexpected one.
  run -127 env -u TRILL_APP sh "$SUBJECT" send --body hi
  # Anchored: a bare *"/Applications"* is satisfied by the `~/Applications`
  # substring alone, so it would pass on a message that dropped the system one.
  [[ "$output" == *" /Applications"* ]]
  [[ "$output" == *"~/Applications"* ]]
  [[ "$output" == *"TRILL_APP"* ]]
}

@test "an unset HOME is 127, not the exit 1 set -u would give" {
  make_bundle "$SYSAPPS/Trill.app" system

  # The system bundle answers first, so the guard is doing its job invisibly.
  run env -u TRILL_APP -u HOME sh "$SUBJECT" ping
  [ "$status" -eq 0 ]

  # With nothing to find, a bare $HOME under `set -u` would exit 1 — one of
  # trill's OWN codes, which a caller reads as "trill ran and rejected the
  # call" rather than "no Trill.app on this Mac".
  rm -rf "$SYSAPPS"
  run -127 env -u TRILL_APP -u HOME sh "$SUBJECT" ping
}

# --- the other two copies of the same list -----------------------------------

# Each of these greps the two bundle paths out of one file and asserts the
# system one comes first. A copy that drifts is silent on a real machine: both
# candidates exist, both work, and only the daemon's VERSION differs.
@test "haus.sh's trill_bin lists /Applications before ~/Applications" {
  # The candidate lines of the `for` in trill_bin(), in file order.
  run bash -c "grep -n 'Applications/Trill.app/Contents/MacOS/Trill' '$REPO/modules/core/haus.sh' | grep -v '^[0-9]*: *#'"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ]
  [[ "${lines[0]}" == *'"/Applications/Trill.app'* ]]
  [[ "${lines[1]}" == *'$HOME/Applications/Trill.app'* ]]
}

@test "the bar's trill pill lists /Applications before ~/Applications" {
  run bash -c "grep -n 'Applications/Trill.app/Contents/MacOS/Trill' '$REPO/modules/bar/sketchybar/plugins/trill.sh' | grep -v '^[0-9]*: *#'"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ]
  [[ "${lines[0]}" == *'"/Applications/Trill.app'* ]]
  [[ "${lines[1]}" == *'${HOME:-}/Applications/Trill.app'* ]]
}

@test "the wrapper itself lists /Applications before ~/Applications" {
  run bash -c "grep -n '^ *\"[^\"]*/Applications/Trill.app\"' '$WRAPPER'"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ]
  [[ "${lines[0]}" == *'"/Applications/Trill.app"'* ]]
  [[ "${lines[1]}" == *'"${HOME:-}/Applications/Trill.app"'* ]]
}

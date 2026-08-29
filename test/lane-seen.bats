#!/usr/bin/env bats
# Hermetic tests for modules/terminal/lanes/lane-seen.sh — "you are looking at
# the lane, so take its trill fin down."
#
# The script runs on EVERY focus change on the machine (AeroSpace's
# `on-focus-changed`, wired in modules/windows), so two properties matter
# equally and neither is observable by eye:
#
#   * it resolves the RIGHT key. The window layer knows a lane as the zmx
#     session `scruff.<repo>.<lane>`; trill knows the same fin as
#     `scruff/<repo>/<lane>`. No split of the session name can recover that —
#     `<repo>` may itself carry a dot (`hausfold.co` is one of ours) — so the
#     boundary comes from scruff's registry, and the dotted-repo case below is
#     the one a naive `${sess##*.}` gets wrong every time.
#   * it does NOTHING the rest of the time. No fin parked, no lane focused,
#     focus that moved on again: each must exit without launching trill.
#
# Everything the subject touches is an env-var away — HOME (the focused-session
# join), SCRUFF_STATE (scruff's ask markers), SCRUFF_BASE (its registry) — so this
# needs no Mac, no tiler and no Trill.app.
#
# ⚠️ trill is stubbed TWICE on purpose. The subject calls the name `trill`,
# which on a haus Mac resolves to the wrapper in /run/current-system/sw/bin
# that the script's own PATH prelude puts ahead of anything a test can
# prepend — so the macOS path is intercepted at $TRILL_APP, the seam that
# wrapper documents, while a runner with no haus at all finds the plain stub
# on PATH. Both write the same file, so the assertions don't care which ran.

bats_require_minimum_version 1.5.0

setup() {
  SUBJECT="$BATS_TEST_DIRNAME/../modules/terminal/lanes/lane-seen.sh"

  export HOME="$BATS_TEST_TMPDIR/home"
  export SCRUFF_STATE="$BATS_TEST_TMPDIR/state"
  export SCRUFF_BASE="$BATS_TEST_TMPDIR/base"
  export HAUS_LANE_SEEN_DWELL=0

  CALLS="$BATS_TEST_TMPDIR/calls"
  export CALLS

  mkdir -p "$HOME/.config/haus/term" "$SCRUFF_STATE/asks" "$SCRUFF_BASE" \
    "$BATS_TEST_TMPDIR/bin" "$BATS_TEST_TMPDIR/Trill.app/Contents/MacOS"

  # Two lanes, one of them in a repo whose NAME contains a dot.
  {
    printf 'ci-main-branch\t/w/hausfold.co\tworktree-ci-main-branch\t/p\t/m\tclaude\n'
    printf 'workshop\t/w/haus\tworktree-workshop\t/p\t/m\tclaude\n'
  } >"$SCRUFF_BASE/registry.tsv"

  cat >"$BATS_TEST_TMPDIR/bin/trill" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$CALLS"
STUB
  cp "$BATS_TEST_TMPDIR/bin/trill" "$BATS_TEST_TMPDIR/Trill.app/Contents/MacOS/Trill"
  chmod +x "$BATS_TEST_TMPDIR/bin/trill" "$BATS_TEST_TMPDIR/Trill.app/Contents/MacOS/Trill"
  export TRILL_APP="$BATS_TEST_TMPDIR/Trill.app"
  export PATH="$PATH:$BATS_TEST_TMPDIR/bin"
}

# The window→session join, faked. Each line of $ANSWERS is one call, so a test
# can make focus MOVE between the first look and the second.
focus_answers() {
  printf '%s\n' "$@" >"$BATS_TEST_TMPDIR/answers"
  cat >"$HOME/.config/haus/term/focused-session.sh" <<'STUB'
#!/usr/bin/env bash
n="$(cat "$BATS_TEST_TMPDIR/answers.n" 2>/dev/null || echo 1)"
sed -n "${n}p" "$BATS_TEST_TMPDIR/answers"
printf '%s' "$((n + 1))" >"$BATS_TEST_TMPDIR/answers.n"
STUB
  chmod +x "$HOME/.config/haus/term/focused-session.sh"
}

calls() { cat "$CALLS" 2>/dev/null || true; }

@test "a dotted repo name is split where scruff's registry says, not at the last dot" {
  touch "$SCRUFF_STATE/asks/scruff.hausfold.co.ci-main-branch"
  focus_answers scruff.hausfold.co.ci-main-branch scruff.hausfold.co.ci-main-branch

  run -0 bash "$SUBJECT"
  [ "$(calls)" = "resolve scruff/hausfold.co/ci-main-branch" ]
}

@test "a lane with no fin outstanding costs nothing" {
  touch "$SCRUFF_STATE/asks/scruff.haus.workshop"
  focus_answers scruff.hausfold.co.ci-main-branch scruff.hausfold.co.ci-main-branch

  run -0 bash "$SUBJECT"
  [ -z "$(calls)" ]
}

@test "an empty ask dir stops before the window is even queried" {
  focus_answers scruff.haus.workshop scruff.haus.workshop

  run -0 bash "$SUBJECT"
  [ -z "$(calls)" ]
  # The gate is ahead of the join: the focus stub was never reached.
  [ ! -e "$BATS_TEST_TMPDIR/answers.n" ]
}

@test "no ask dir at all opens the gate rather than closing it" {
  rm -rf "$SCRUFF_STATE/asks"
  focus_answers scruff.haus.workshop scruff.haus.workshop

  run -0 bash "$SUBJECT"
  [ "$(calls)" = "resolve scruff/haus/workshop" ]
}

@test "focus that moved on again is not a lane you looked at" {
  touch "$SCRUFF_STATE/asks/scruff.haus.workshop"
  focus_answers scruff.haus.workshop term.something-else

  run -0 bash "$SUBJECT"
  [ -z "$(calls)" ]
}

@test "a window that is not a lane is left alone" {
  touch "$SCRUFF_STATE/asks/scruff.haus.workshop"
  focus_answers term.abc123 term.abc123

  run -0 bash "$SUBJECT"
  [ -z "$(calls)" ]
}

@test "a lane the registry has never heard of resolves nothing" {
  touch "$SCRUFF_STATE/asks/scruff.haus.ghost"
  focus_answers scruff.haus.ghost scruff.haus.ghost

  run -0 bash "$SUBJECT"
  [ -z "$(calls)" ]
}

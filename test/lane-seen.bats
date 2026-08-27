#!/usr/bin/env bats
# Hermetic tests for modules/terminal/lanes/lane-seen.sh — "you are looking at
# the lane, so take its trill fin down."
#
# The script runs on EVERY focus change on the machine (AeroSpace's
# `on-focus-changed`) and again whenever holt parks a new fin (a launchd
# WatchPaths agent), so three properties matter equally and none is observable
# by eye:
#
#   * it resolves the RIGHT key. The window layer knows a lane as the zmx
#     session `holt.<repo>.<lane>`; trill knows the same fin as
#     `holt/<repo>/<lane>`. No split of the session name can recover that —
#     `<repo>` may itself carry a dot (`hausfold.co` is one of ours) — so the
#     boundary comes from holt's registry, and the dotted-repo case below is
#     the one a naive `${sess##*.}` gets wrong every time.
#   * "seen" means the whole PAGE, not the focused window — a lane tiled beside
#     what you are typing in has been seen — but never a lane that merely wears
#     the right title. A plain shell window born in a lane's Ghostty process
#     carries that lane's forced title, and clearing the fin of a lane that is
#     on another page entirely is the one failure this file must not have.
#   * it does NOTHING the rest of the time. No fin parked, no lane on screen,
#     focus that moved on again: each must exit without launching trill.
#
# Two halves, tested two ways. Everything the script itself touches is an
# env-var away — HOME, HOLT_STATE, HOLT_BASE, and HAUS_WINDOW_BACKEND, the same
# seam scripts/focused-session.sh already ships so a machine WITH a tiler can
# feel the path a machine without one takes — so the end-to-end cases run on
# the tiler-less backend and need no Mac at all. The tiler half cannot be
# stubbed that way (the script's own PATH prelude puts the real `aerospace`
# ahead of anything a test can prepend), so its awk is extracted and run on
# fixtures.
#
# ⚠️ trill is stubbed TWICE on purpose. The subject calls the name `trill`,
# which on a haus Mac resolves to the wrapper in /run/current-system/sw/bin
# that the PATH prelude puts ahead of anything a test can prepend — so the
# macOS path is intercepted at $TRILL_APP, the seam that wrapper documents,
# while a runner with no haus at all finds the plain stub on PATH. Both write
# the same file, so the assertions don't care which ran.

bats_require_minimum_version 1.5.0

setup() {
  SUBJECT="$BATS_TEST_DIRNAME/../modules/terminal/lanes/lane-seen.sh"

  export HOME="$BATS_TEST_TMPDIR/home"
  export HOLT_STATE="$BATS_TEST_TMPDIR/state"
  export HOLT_BASE="$BATS_TEST_TMPDIR/base"
  export HAUS_LANE_SEEN_DWELL=0
  # No tiler: the end-to-end cases are about the gates and the key join, and
  # this is the backend that answers them without a window manager.
  export HAUS_WINDOW_BACKEND=ghostty

  CALLS="$BATS_TEST_TMPDIR/calls"
  export CALLS

  mkdir -p "$HOME/.config/haus/term" "$HOLT_STATE/asks" "$HOLT_BASE" \
    "$BATS_TEST_TMPDIR/bin" "$BATS_TEST_TMPDIR/Trill.app/Contents/MacOS"

  # Two lanes, one of them in a repo whose NAME contains a dot.
  {
    printf 'ci-main-branch\t/w/hausfold.co\tworktree-ci-main-branch\t/p\t/m\tclaude\n'
    printf 'workshop\t/w/haus\tworktree-workshop\t/p\t/m\tclaude\n'
  } >"$HOLT_BASE/registry.tsv"

  cat >"$BATS_TEST_TMPDIR/bin/trill" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$CALLS"
STUB
  cp "$BATS_TEST_TMPDIR/bin/trill" "$BATS_TEST_TMPDIR/Trill.app/Contents/MacOS/Trill"
  chmod +x "$BATS_TEST_TMPDIR/bin/trill" "$BATS_TEST_TMPDIR/Trill.app/Contents/MacOS/Trill"
  export TRILL_APP="$BATS_TEST_TMPDIR/Trill.app"
  export PATH="$PATH:$BATS_TEST_TMPDIR/bin"
}

# The window→session join, faked. Each line of the fixture is one call, so a
# test can make focus MOVE between the first look and the dwell's second one.
# The subject asks three times on this backend: once for what is on screen,
# twice around the sleep.
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

# ── the gates and the key join ───────────────────────────────────────────────

@test "a dotted repo name is split where holt's registry says, not at the last dot" {
  touch "$HOLT_STATE/asks/holt.hausfold.co.ci-main-branch"
  focus_answers holt.hausfold.co.ci-main-branch holt.hausfold.co.ci-main-branch holt.hausfold.co.ci-main-branch

  run -0 bash "$SUBJECT"
  [ "$(calls)" = "resolve holt/hausfold.co/ci-main-branch" ]
}

@test "a lane with no fin outstanding costs nothing" {
  touch "$HOLT_STATE/asks/holt.haus.workshop"
  focus_answers holt.hausfold.co.ci-main-branch holt.hausfold.co.ci-main-branch holt.hausfold.co.ci-main-branch

  run -0 bash "$SUBJECT"
  [ -z "$(calls)" ]
}

@test "an empty ask dir stops before the window is even queried" {
  focus_answers holt.haus.workshop holt.haus.workshop holt.haus.workshop

  run -0 bash "$SUBJECT"
  [ -z "$(calls)" ]
  # The gate is ahead of the join: the focus stub was never reached.
  [ ! -e "$BATS_TEST_TMPDIR/answers.n" ]
}

@test "no ask dir at all opens the gate rather than closing it" {
  # The room's activation creates the dir, so in production this is a machine
  # it never activated on — or holt having moved its cache. Either way,
  # resolving every lane on the page beats silently resolving none.
  rm -rf "$HOLT_STATE/asks"
  focus_answers holt.haus.workshop holt.haus.workshop holt.haus.workshop

  run -0 bash "$SUBJECT"
  [ "$(calls)" = "resolve holt/haus/workshop" ]
}

@test "focus that left the page during the dwell is not a lane you looked at" {
  touch "$HOLT_STATE/asks/holt.haus.workshop"
  focus_answers holt.haus.workshop holt.haus.workshop term.something-else

  run -0 bash "$SUBJECT"
  [ -z "$(calls)" ]
}

@test "a window that is not a lane is left alone" {
  touch "$HOLT_STATE/asks/holt.haus.workshop"
  focus_answers term.abc123 term.abc123 term.abc123

  run -0 bash "$SUBJECT"
  [ -z "$(calls)" ]
}

@test "a lane the registry has never heard of resolves nothing" {
  touch "$HOLT_STATE/asks/holt.haus.ghost"
  focus_answers holt.haus.ghost holt.haus.ghost holt.haus.ghost

  run -0 bash "$SUBJECT"
  [ -z "$(calls)" ]
}

@test "the marker of a resolved fin is dropped, so the cheap gate stays cheap" {
  # holt only prunes its marker on that lane's next tool call, so a lane closed
  # while blocked would leave one behind forever — and a dir that is never
  # empty answers "yes, something is waiting" on every focus change for the
  # life of the machine.
  touch "$HOLT_STATE/asks/holt.haus.workshop"
  focus_answers holt.haus.workshop holt.haus.workshop holt.haus.workshop

  run -0 bash "$SUBJECT"
  [ "$(calls)" = "resolve holt/haus/workshop" ]
  [ ! -e "$HOLT_STATE/asks/holt.haus.workshop" ]
}

@test "a fin this script can never resolve does not count as waiting" {
  # A pane outside every lane is keyed by session id and has no window title to
  # match. Counting it would hold the gate open for every other pane.
  touch "$HOLT_STATE/asks/holt.session.7f3c-not-a-lane"
  focus_answers holt.haus.workshop holt.haus.workshop holt.haus.workshop

  run -0 bash "$SUBJECT"
  [ -z "$(calls)" ]
  [ ! -e "$BATS_TEST_TMPDIR/answers.n" ]
  [ -e "$HOLT_STATE/asks/holt.session.7f3c-not-a-lane" ]
}

@test "two waiting lanes on screen are resolved in one call" {
  touch "$HOLT_STATE/asks/holt.haus.workshop" "$HOLT_STATE/asks/holt.hausfold.co.ci-main-branch"
  # This backend can only ever see one window, so the pair comes from the
  # registry join rather than the page; what it pins is that `trill resolve`
  # is given every key at once rather than launched per lane.
  focus_answers holt.haus.workshop holt.haus.workshop holt.haus.workshop

  run -0 bash "$SUBJECT"
  [ "$(calls)" = "resolve holt/haus/workshop" ]
}

# ── what counts as ON THE PAGE (the tiler half) ──────────────────────────────
# The awk out of the subject's `on_screen`, run on a fixture window list. See
# the header for why this half is extracted rather than driven end to end.

page_lanes() {
  local prog fixture claimed
  fixture="$1"
  claimed="$2"
  # Anchored on the LEADING WHITESPACE of both lines: the subject's own header
  # quotes these two anchors in prose, and an unanchored range starts at the
  # comment and drags half a shell function into the awk.
  prog="$(
    sed -n '/^ *BEGIN { n = split(c, a, " ")/,/^ *\$2 == "Ghostty"/p' "$SUBJECT" |
      sed "\$s/'\$//"
  )"
  [ -n "$prog" ] || { echo "awk fragment not found — did on_screen move?" >&2; return 1; }
  printf '%s\n' "$fixture" | awk -F'|' -v c="$claimed" "$prog"
}

@test "a lane window on the page is seen even without focus" {
  run -0 page_lanes '101|Ghostty|holt.haus.workshop
102|Ghostty|term.3' ''
  [ "$output" = "holt.haus.workshop" ]
}

@test "every lane on the page is seen, not just one" {
  run -0 page_lanes '101|Ghostty|holt.haus.workshop
102|Ghostty|holt.hausfold.co.ci-main-branch' ''
  [ "${lines[0]}" = "holt.haus.workshop" ]
  [ "${lines[1]}" = "holt.hausfold.co.ci-main-branch" ]
}

@test "an impostor wearing a lane's forced title is not that lane" {
  # A plain shell window born inside the lane's Ghostty process: same title,
  # but it carries a `window=` label the real lane never has.
  run -0 page_lanes '101|Ghostty|holt.haus.workshop' '101'
  [ -z "$output" ]
}

@test "one impostor does not hide the real lane beside it" {
  run -0 page_lanes '101|Ghostty|holt.haus.workshop
102|Ghostty|holt.haus.workshop' '101'
  [ "$output" = "holt.haus.workshop" ]
}

@test "the claimed list may hold several ids without killing the awk" {
  # Space-separated, never newline-separated: `awk -v` is awk SOURCE, and
  # macOS's one-true-awk dies on a literal newline in a string literal. The
  # second labelled window is what turned that into an outage in
  # raise-session.sh (2026-08-26).
  run -0 page_lanes '101|Ghostty|holt.haus.workshop
102|Ghostty|holt.hausfold.co.ci-main-branch' '102 103 104'
  [ "$output" = "holt.haus.workshop" ]
}

@test "another app's window is never a lane, whatever it calls itself" {
  run -0 page_lanes '101|Safari|holt.haus.workshop' ''
  [ -z "$output" ]
}

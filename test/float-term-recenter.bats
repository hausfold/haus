#!/usr/bin/env bats
# Hermetic tests for `recenter` in modules/terminal/scripts/float-term.sh — the
# pass that centres a spawned popup on the size it actually IS.
#
# Why a suite. The bug this closes shipped, was invisible for months, and was
# only ever going to be found by someone looking at a big enough screen. Three
# ⌘Space popups — rebuild, settings, add-app — pass BOTH a pixel size and a cell
# grid (`--w 750 --h 400 --cols 80 --rows 20`), and those disagree: Ghostty
# rounds to whole cells and refuses to shrink below its grid, so `set_frame`'s
# size half is quietly declined while its position half sticks. The window is
# planted at the origin that would have centred the size we asked for, and is
# then a different size. Measured 2026-08-23 on a 2560×1440 Studio Display: the
# rebuild popup asks 750×400, is 942×554, and lands 96pt right and 77pt below
# centre. Nothing in a build, a lint or a rebuild can see that.
#
# The subject is arithmetic over two rectangles, so it needs no Mac, no window
# and no AX: `window_size`, `screen_probe` and `set_frame` are stubbed and the
# assertion is the frame `recenter` would have set. The numbers in the first two
# cases are the REAL ones off that screenshot, which is what makes this a
# regression test rather than a restatement of the formula.

bats_require_minimum_version 1.5.0

# Load `recenter` alone, with its three collaborators replaced. Defined per test
# rather than in `setup`, because a stub that leaks between cases is how a suite
# starts passing for the wrong reason.
load_recenter() { # AW AH SCREEN
  eval "$(sed -n '/^recenter() {/,/^}/p' \
    "$BATS_TEST_DIRNAME/../modules/terminal/scripts/float-term.sh")"
  eval "window_size() { printf '%s %s\n' '$1' '$2'; }"
  eval "screen_probe() { printf '%s\n' '$3'; }"
  set_frame() { printf 'x=%s y=%s w=%s h=%s\n' "$2" "$3" "$4" "$5"; }
}

@test "external: centres the size the window really is, not the one we asked for" {
  # visibleFrame 0,0 2560×1440 — a Studio Display reserves nothing, not even a
  # menu bar, which is half of why this showed up here and not on the built-in.
  load_recenter 942 554 "0 0 2560 1440 0 1"
  run recenter 999 905 520 750 400
  [ "$status" -eq 0 ]
  # 809 + 942/2 = 1280 and 443 + 554/2 = 720: the centre of the display.
  [ "$output" = "x=809 y=443 w=942 h=554" ]
}

@test "built-in: centres in the VISIBLE frame, so the notch band still counts" {
  # visibleFrame 2560,266 1512×950 — 32pt shorter than the frame, at the top
  # only, which is the notch. Centring on the full frame would tuck the title
  # bar under it.
  load_recenter 942 554 "2560 266 1512 950 1 1"
  run recenter 999 2941 541 750 400
  [ "$output" = "x=2845 y=464 w=942 h=554" ]
}

@test "a window that IS the requested size is left alone" {
  # No move means no second AX round trip and no chance of a visible jump. The
  # exact modes (--tiled, --match-focused) never reach recenter at all; this is
  # the case where a centred mode happens to agree with its grid.
  load_recenter 750 400 "0 0 2560 1440 0 1"
  run recenter 999 905 520 750 400
  [ "$output" = "" ]
}

@test "a window bigger than the display clamps to the visible origin" {
  # Centring something oversized gives a NEGATIVE origin, which puts the
  # top-left off-screen and the title bar out of reach. Overflowing off the
  # right is recoverable; off the top-left is not.
  load_recenter 1800 1100 "2560 266 1512 950 1 1"
  run recenter 999 2941 541 750 400
  [ "$output" = "x=2560 y=266 w=1800 h=1100" ]
}

@test "an unreadable size leaves the window where it is" {
  # AX can decline — the window may not be exposed yet, or the process may have
  # died. A popup that is off-centre is a nuisance; one moved to 0×0 or to a
  # garbage origin is lost.
  load_recenter "" "" "0 0 2560 1440 0 1"
  run recenter 999 905 520 750 400
  [ "$output" = "" ]
}

@test "a non-numeric size is refused too, not arithmetic'd" {
  # `$(( ))` on a word is a `set -u`-shaped death in some shells and a silent 0
  # in others; either way the guard belongs before the maths.
  load_recenter "wide" "tall" "0 0 2560 1440 0 1"
  run recenter 999 905 520 750 400
  [ "$output" = "" ]
}

@test "no pid: does nothing rather than talking to process 0" {
  load_recenter 942 554 "0 0 2560 1440 0 1"
  run recenter "" 905 520 750 400
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

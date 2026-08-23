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
# and no AX: `window_frame`, `screen_probe` and `set_frame` are stubbed and the
# assertion is the frame `recenter` would have set. The numbers in the first two
# cases are the REAL ones off that screenshot, which is what makes this a
# regression test rather than a restatement of the formula.
#
# ⚠️ The subject is extracted by `sed`, because float-term.sh cannot be sourced —
# its dispatch at the bottom exits 2 on no arguments. So `recenter` must keep a
# `^recenter() {` opening line and a closing `}` in column 0. If either moves,
# the eval yields nothing and every case here fails with "command not found",
# which is the loud failure and the reason this is acceptable.

bats_require_minimum_version 1.5.0

# Load `recenter` alone, with its three collaborators replaced. Defined per test
# rather than in `setup`, because a stub that leaks between cases is how a suite
# starts passing for the wrong reason.
#
# `set -u` on purpose: the script sets it at the top, so a case that only passes
# with unset variables tolerated would be testing a function nobody runs.
#
# The screen_probe stub echoes the probe point it was handed. Which point that
# is — the WINDOW's centre, not the cursor's and not the rectangle geom picked —
# is the one design decision here that a jumping popup on a two-monitor desk
# would punish, so it is asserted rather than assumed.
load_recenter() { # FRAME
  set -u
  eval "$(sed -n '/^recenter() {/,/^}/p' \
    "$BATS_TEST_DIRNAME/../modules/terminal/scripts/float-term.sh")"
  eval "window_frame() { printf '%s\n' '$1'; }"
  set_frame() { printf 'x=%s y=%s w=%s h=%s\n' "$2" "$3" "$4" "$5"; }
}

# A faithful-enough screen_probe over the real desk, so the probe POINT is
# load-bearing. An earlier version of this stub returned the same rectangle
# whichever point it was handed, and a mutation swapping the window's centre for
# the intended rect's went undetected — the suite asserted the decision in a
# comment and tested nothing. The two displays, in top-left coordinates:
#
#   external  frame 0,0 2560×1440      visibleFrame 0,0 2560×1440
#   built-in  frame 2560,234 1512×982  visibleFrame 2560,266 1512×950
#
# and, matching the real function, a point on NO display falls back to
# screens[0]'s frame with hit = 0 rather than to nothing.
screen_probe() {
  local x="$HAUS_PROBE_X" y="$HAUS_PROBE_Y"
  if [ "$x" -ge 0 ] && [ "$x" -lt 2560 ] && [ "$y" -ge 0 ] && [ "$y" -lt 1440 ]; then
    printf '0 0 2560 1440 0 1\n'
  elif [ "$x" -ge 2560 ] && [ "$x" -lt 4072 ] && [ "$y" -ge 234 ] && [ "$y" -lt 1216 ]; then
    printf '2560 266 1512 950 1 1\n'
  else
    printf '0 0 2560 1440 0 0\n'
  fi
}

@test "external: centres the size the window really is, not the one we asked for" {
  load_recenter "905 520 942 554"
  run recenter 999 905 520 750 400
  [ "$status" -eq 0 ]
  # 809 + 942/2 = 1280 and 443 + 554/2 = 720: the centre of the display.
  [ "$output" = "x=809 y=443 w=942 h=554" ]
}

@test "built-in: centres in the VISIBLE frame, so the notch band still counts" {
  load_recenter "2941 541 942 554"
  run recenter 999 2941 541 750 400
  [ "$output" = "x=2845 y=464 w=942 h=554" ]
}

@test "the display comes from the WINDOW's centre, not the intended rect's" {
  # --pin hands the window to aerospace, which moves it to the summoning
  # workspace — on the other monitor, whenever mouseFollowsFocus is off. Probing
  # where geom pointed would drag it back off its own workspace.
  load_recenter "2941 541 942 554"
  run recenter 999 905 520 750 400
  [ "$output" = "x=2845 y=464 w=942 h=554" ]
}

@test "a window parked on no display falls back to the intended rect" {
  # aerospace parks the windows of a hidden workspace off the bottom-right
  # corner. That point is on no screen (hit = 0), so its frame cannot answer
  # "which display", and the rectangle geom picked is the next best thing.
  #
  # The intended rect is on the BUILT-IN on purpose. A no-hit probe returns
  # screens[0] — the external — so an intended rect on the external would give
  # the same answer whether the fallback ran or not, and this case would pass
  # with the fallback deleted.
  load_recenter "99000 99000 942 554"
  run recenter 999 2941 541 750 400
  [ "$output" = "x=2845 y=464 w=942 h=554" ]
}

@test "cell rounding alone is not worth a visible jump" {
  # Ghostty rounds ANY size to whole cells, so a popup passing no grid flags
  # still misses by a few px. agent-peek is that caller. Moving it 3px is a
  # flicker bought for nothing.
  load_recenter "903 518 754 404"
  run recenter 999 905 520 750 400
  [ "$output" = "" ]
}

@test "but a miss bigger than rounding still moves" {
  # 20pt is the line. 96 and 77 — the measured miss — are well past it.
  load_recenter "905 520 942 554"
  run recenter 999 905 520 750 400
  [ -n "$output" ]
}

@test "a window bigger than the display clamps to the visible origin" {
  # Centring something oversized gives a NEGATIVE origin, which puts the
  # top-left off-screen and the title bar out of reach. Overflowing off the
  # right is recoverable; off the top-left is not.
  load_recenter "2941 541 1800 1100"
  run recenter 999 2941 541 750 400
  [ "$output" = "x=2560 y=266 w=1800 h=1100" ]
}

@test "a 0x0 frame is refused, not centred" {
  # All digits, so the numeric guard passes it. AX reports 0×0 for a window
  # mid-teardown or one that never drew; centring it would plant a collapsed
  # popup at the exact centre of the screen. Same 200pt floor focused_frame and
  # place use.
  load_recenter "905 520 0 0"
  run recenter 999 905 520 750 400
  [ "$output" = "" ]
}

@test "a frame under the 200pt floor is refused" {
  load_recenter "905 520 199 199"
  run recenter 999 905 520 750 400
  [ "$output" = "" ]
}

@test "an unreadable frame leaves the window where it is" {
  # AX can decline — the window may not be exposed yet, or the process may have
  # died. A popup that is off-centre is a nuisance; one moved to 0×0 or to a
  # garbage origin is lost.
  load_recenter ""
  run recenter 999 905 520 750 400
  [ "$output" = "" ]
}

@test "a non-numeric frame is refused too, not arithmetic'd" {
  load_recenter "905 520 wide tall"
  run recenter 999 905 520 750 400
  [ "$output" = "" ]
}

@test "a truncated frame is refused" {
  load_recenter "905 520 942"
  run recenter 999 905 520 750 400
  [ "$output" = "" ]
}

@test "no pid: does nothing rather than talking to process 0" {
  load_recenter "905 520 942 554"
  run recenter "" 905 520 750 400
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

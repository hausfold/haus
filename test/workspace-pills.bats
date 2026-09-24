#!/usr/bin/env bats
# Hermetic tests for modules/bar/sketchybar/plugins/workspace_lib.sh — what a
# workspace pill says, and the buried pill beside the front app.
#
# ── what is actually hard here ───────────────────────────────────────────────
# Every rule below is invisible when it breaks: a pill with one pip too few, a
# ring on the wrong workspace, a buried pill that never lights. Nothing errors;
# the bar just says something slightly untrue, forever.
#
#   * a pill stands for its workspace AND its pages, so `T` counts `T/haus`'s
#     windows and is lit while `T/haus` is focused — but never `TT/x`'s.
#   * one window draws no pips; the pips start at two.
#   * a window off the tiling grid is a HOLLOW pip, and "off the grid" is
#     everything that is not tiles or accordion — a minimised window too.
#   * every state writes every property another state touches (the border
#     above all), or the previous state's is left standing.
#   * the buried pill asks hausrect only when there is something to ask, never
#     about the focused window, and never guesses when hausrect is missing.
#
# The subject is SOURCED into a fresh bash per case, with aerospace and
# hausrect replaced by the two stubs below through the WS_AEROSPACE /
# WS_HAUSRECT overrides the lib reads — so nothing here can ever answer from
# the real desktop of the Mac the suite runs on. $WS_BASH picks the shell:
# point it at /bin/bash on a Mac to hold the file to 3.2, which is what the
# bar runs it under.

bats_require_minimum_version 1.5.0

LIB() { printf '%s' "$BATS_TEST_DIRNAME/../modules/bar/sketchybar/plugins/workspace_lib.sh"; }

setup() {
  STUB="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$STUB"
  # The fixture: $FOCUSED, $FOCUSED_WIN (+ $FULLSCREEN), $VISIBLE (space-
  # separated) and $WINDOWS — one window per line, `ws|id|layout|app|title`,
  # turned into the unit-separated rows AeroSpace's --format hands the lib.
  cat >"$STUB/aerospace" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$BATS_TEST_TMPDIR/aerospace.log"
case "$*" in
  "list-workspaces --focused") printf '%s\n' "$FOCUSED" ;;
  list-windows\ --focused*)
    [ -n "${FOCUSED_WIN:-}" ] && printf '%s\037%s\n' "$FOCUSED_WIN" "${FULLSCREEN:-false}" ;;
  *--visible*) printf '%s\n' $VISIBLE ;;
  list-windows\ --all*) printf '%s\n' "$WINDOWS" | grep . | tr '|' '\037' ;;
esac
EOF
  # hausrect --visible: $COVER is `id:percent …` in STACKING order, front to
  # back — the order the real one prints in, whatever order it was asked in.
  # Every call is logged so a case can assert it was (or was not) asked.
  cat >"$STUB/hausrect" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$BATS_TEST_TMPDIR/hausrect.log"
shift
for c in $COVER; do
  for id in "$@"; do
    [ "${c%%:*}" = "$id" ] && printf '%s\t%s\n' "$id" "${c#*:}"
  done
done
exit 0
EOF
  chmod +x "$STUB/aerospace" "$STUB/hausrect"
  export BATS_TEST_TMPDIR
  FOCUSED=1 FOCUSED_WIN="" FULLSCREEN=false VISIBLE="" WINDOWS="" COVER=""
  export FOCUSED FOCUSED_WIN FULLSCREEN VISIBLE WINDOWS COVER
  export BAR_WS_WINDOWS=dots
}

# paint <cmd…> — source the lib against the stubs, take a snapshot, run <cmd>,
# print WS_ARGS one per line.
paint() {
  "${WS_BASH:-bash}" -c '
    BASE=0xff000001 TEXT=0xff000002 SURFACE0=0xff000003 OVERLAY1=0xff000004
    MAUVE=0xff000005 YELLOW=0xff000006 BAR_FONT=Mono FS_TINY=12.0 FS_PIP=10.0
    WS_AEROSPACE='"$STUB"'/aerospace
    WS_HAUSRECT="${HAUSRECT-'"$STUB"'/hausrect}"
    WS_BURIED_CACHE='"$BATS_TEST_TMPDIR"'/buried-cache
    WORKSPACES=(1 2 T TT B)
    HOME='"$BATS_TEST_TMPDIR"'
    source "'"$(LIB)"'"
    ws_snapshot
    WS_ARGS=()
    '"$*"'
    printf "%s\n" "${WS_ARGS[@]}"
  '
}

# pill <ws> — the one pill's args, as a single line.
pill() {
  paint ws_pills_args 0xffaaaaaa | awk -v id="space.$1" '
    $0 == "--set" { getline name; on = (name == id); next }
    on { printf "%s ", $0 }
    END { print "" }'
}

# ── pips ─────────────────────────────────────────────────────────────────────

@test "one window: lit, no pips" {
  WINDOWS="1|10|h_tiles|Zen|a"
  run -0 pill 1
  [[ "$output" == *"drawing=on"* ]]
  [[ "$output" == *"label.drawing=off"* ]]
  [[ "$output" == *"icon.padding_right=10"* ]]
}

@test "three tiled windows: three filled pips" {
  WINDOWS=$'1|10|h_tiles|Zen|a\n1|11|h_tiles|Zen|b\n1|12|v_tiles|Figma|c'
  run -0 pill 1
  [[ "$output" == *"label=●●● "* ]]
  [[ "$output" == *"icon.padding_right=5"* ]]
}

@test "a floating window is a hollow pip, after the tiled ones" {
  WINDOWS=$'1|10|floating|FaceTime|a\n1|11|h_tiles|Zen|b\n1|12|h_accordion|Zen|c'
  run -0 pill 1
  [[ "$output" == *"label=●●○ "* ]]
}

@test "a minimised window is off the grid too" {
  WINDOWS=$'1|10|h_tiles|Zen|a\n1|11|macos_native_minimized|Zen|b'
  run -0 pill 1
  [[ "$output" == *"label=●○ "* ]]
}

@test "past six windows: the number, ringed when any is loose" {
  WINDOWS=$(for i in 1 2 3 4 5 6; do echo "1|1$i|h_tiles|Zen|x"; done; echo "1|20|floating|Finder|y")
  run -0 pill 1
  [[ "$output" == *"label=7○ "* ]]
  [[ "$output" == *"label.font=Mono:Bold:12.0"* ]]
}

@test "count mode: the number from two windows up" {
  BAR_WS_WINDOWS=count
  WINDOWS=$'1|10|h_tiles|Zen|a\n1|11|h_tiles|Zen|b'
  run -0 pill 1
  [[ "$output" == *"label=2 "* ]]
}

@test "off: no pips at all" {
  BAR_WS_WINDOWS=off
  WINDOWS=$'1|10|h_tiles|Zen|a\n1|11|floating|Zen|b'
  run -0 pill 1
  [[ "$output" == *"label.drawing=off"* ]]
}

# ── which pill, which state ──────────────────────────────────────────────────

@test "a page's windows count on its workspace's pill, and light it" {
  FOCUSED=T/haus
  WINDOWS=$'T/haus|10|h_tiles|Ghostty|a\nT/scruff|11|h_tiles|Ghostty|b\nTT/x|12|h_tiles|Ghostty|c'
  run -0 pill T
  [[ "$output" == *"background.color=0xffaaaaaa"* ]]
  [[ "$output" == *"label=●● "* ]]
  run -0 pill TT
  [[ "$output" == *"background.color=0xff000003"* ]]
  [[ "$output" == *"label.drawing=off"* ]]
}

@test "focused pips are the ink at two-thirds; unfocused are dim" {
  WINDOWS=$'1|10|h_tiles|Zen|a\n1|11|h_tiles|Zen|b\n2|12|h_tiles|Zen|c\n2|13|h_tiles|Zen|d'
  run -0 pill 1
  [[ "$output" == *"label.color=0xaa000001"* ]]
  run -0 pill 2
  [[ "$output" == *"label.color=0xff000004"* ]]
}

@test "empty and elsewhere: hidden; empty and focused: lit" {
  FOCUSED=1
  run -0 pill 1
  [[ "$output" == *"drawing=on"* ]]
  run -0 pill 2
  [ "$output" = "drawing=off " ]
}

@test "shown on another display: ringed, even when empty" {
  VISIBLE="1 B"
  run -0 pill B
  [[ "$output" == *"drawing=on"* ]]
  [[ "$output" == *"background.border_width=2"* ]]
  run -0 pill 1
  [[ "$output" == *"background.border_width=0"* ]]
}

# ── buried ───────────────────────────────────────────────────────────────────

buried() { paint ws_buried_args | tr '\n' ' '; }

@test "a floating window under a quarter visible: named, and a click raises it" {
  FOCUSED_WIN=11
  WINDOWS=$'1|10|floating|FaceTime|call\n1|11|h_tiles|Zen|web'
  COVER="10:5"
  run -0 buried
  [[ "$output" == *"drawing=on"* ]]
  [[ "$output" == *"label=FaceTime "* ]]
  [[ "$output" == *"click_script=$STUB/aerospace focus --window-id 10"* ]]
}

@test "a floating window you can still see is not buried" {
  FOCUSED_WIN=11
  WINDOWS=$'1|10|floating|FaceTime|call\n1|11|h_tiles|Zen|web'
  COVER="10:60"
  run -0 buried
  [[ "$output" == *"drawing=off"* ]]
}

@test "two buried: the front-most is named, the rest counted" {
  FOCUSED_WIN=12
  WINDOWS=$'1|10|floating|FaceTime|a\n1|11|floating|Finder|b\n1|12|h_tiles|Zen|c'
  COVER="11:0 10:3"
  run -0 buried
  [[ "$output" == *"label=Finder +1 "* ]]
  [[ "$output" == *"--window-id 11"* ]]
}

@test "the focused window is never asked about, and one window is never asked at all" {
  FOCUSED_WIN=10
  WINDOWS=$'1|10|floating|FaceTime|a\n1|11|h_tiles|Zen|b'
  COVER="10:0"
  run -0 buried
  [[ "$output" == *"drawing=off"* ]]
  [ ! -e "$BATS_TEST_TMPDIR/hausrect.log" ]

  WINDOWS=$'1|10|floating|FaceTime|a'
  FOCUSED_WIN=""
  run -0 buried
  [[ "$output" == *"drawing=off"* ]]
  [ ! -e "$BATS_TEST_TMPDIR/hausrect.log" ]
}

@test "only the FOCUSED workspace's floats, and only while hausrect is there" {
  FOCUSED_WIN=11
  WINDOWS=$'2|10|floating|FaceTime|a\n1|11|h_tiles|Zen|b\n1|12|h_tiles|Zen|c'
  COVER="10:0"
  run -0 buried
  [[ "$output" == *"drawing=off"* ]]

  WINDOWS=$'1|10|floating|FaceTime|a\n1|11|h_tiles|Zen|b'
  export HAUSRECT="$BATS_TEST_TMPDIR/nope"
  run -0 buried
  [[ "$output" == *"drawing=off"* ]]
}

@test "a quiet tick reuses the answer; a change of focus asks again" {
  FOCUSED_WIN=11
  WINDOWS=$'1|10|floating|FaceTime|call\n1|11|h_tiles|Zen|web\n1|12|h_tiles|Zen|web2'
  COVER="10:5"
  run -0 buried
  run -0 buried
  [[ "$output" == *"label=FaceTime "* ]]
  [ "$(wc -l <"$BATS_TEST_TMPDIR/hausrect.log")" -eq 1 ]

  FOCUSED_WIN=12
  run -0 buried
  [ "$(wc -l <"$BATS_TEST_TMPDIR/hausrect.log")" -eq 2 ]
}

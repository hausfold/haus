#!/usr/bin/env bats
# Hermetic tests for gravity's EVICTION tell in
# modules/bar/sketchybar/plugins/empty_workspace.sh.
#
# ── the bug this suite pins ──────────────────────────────────────────────────
# A lane is its own Ghostty process. ⌃C out of the agent ends the shell, Ghostty
# quits with its last window, macOS activates the next app, and AeroSpace
# follows that app to its workspace — all before the plugin sees an event. Both
# older tells key on standing where the window died, so the first event arrived
# on the browser's workspace and read as navigation: tabbing through T/<repo>
# pages, closing one dropped you in the browser while sibling lanes ran one
# page over.
#
# The traps are the two ways to leave a workspace empty on purpose: a
# throw-and-follow (the window survives, on the workspace you followed it to)
# and walking off a page whose last window is still alive. Neither may hop.
#
# Hermetic: `aerospace` is a stub reading its answers from files, state lives
# in the test's tmpdir, and the one move gravity makes is recorded, not made.

bats_require_minimum_version 1.5.0

SUBJECT="$BATS_TEST_DIRNAME/../modules/bar/sketchybar/plugins/empty_workspace.sh"

setup() {
  AE="$BATS_TEST_TMPDIR/ae"
  mkdir -p "$AE"
  cat >"$AE/aerospace" <<EOF
#!/bin/bash
case "\$1 \$2" in
  "list-workspaces --focused") cat "$AE/focused" ;;
  "list-workspaces --monitor") cat "$AE/nonempty" ;;
  "list-windows --focused")    cat "$AE/fwid" ;;
  "list-windows --all")        cat "$AE/allwids" ;;
  "workspace "*)               echo "\$2" >"$AE/jumped" ;;
esac
EOF
  chmod +x "$AE/aerospace"
  export EMPTY_WS_AEROSPACE="$AE/aerospace" EMPTY_WS_DIR="$BATS_TEST_TMPDIR"
  : >"$AE/jumped"
}

# world <focused> <focused window id> <all window ids> <nonempty workspaces…>
world() {
  printf '%s\n' "$1" >"$AE/focused"
  printf '%s' "$2" >"$AE/fwid"
  printf '%s\n' $3 >"$AE/allwids"
  shift 3
  printf '%s\n' "$@" >"$AE/nonempty"
}

event() {
  SENDER=space_windows_change bash "$SUBJECT"
  wait_fork
}

# The fork is backgrounded and polls at most 20 × 10 ms; give it a margin.
wait_fork() { sleep 0.5; }

@test "a lane's process quits, macOS drops you on the browser → back into the T family" {
  world "T/haus" 11 "11 12 20" T/haus T/workshop W
  event
  # ⌃C: window 11 is gone, T/haus empties, AeroSpace followed the browser to W.
  world "W" 20 "12 20" T/workshop W
  event
  [ "$(cat "$AE/jumped")" = "T/workshop" ]
}

@test "evicted with the whole family empty → macOS's pick stands" {
  world "T/haus" 11 "11 20" T/haus W
  event
  world "W" 20 "20" W
  event
  [ -z "$(cat "$AE/jumped")" ]
}

@test "evicted onto a sibling page → no second hop" {
  world "T/haus" 11 "11 12" T/haus T/workshop
  event
  world "T/workshop" 12 "12" T/workshop
  event
  [ -z "$(cat "$AE/jumped")" ]
}

@test "throw-and-follow: the window survives, so the empty page is not an eviction" {
  world "T/haus" 11 "11 12" T/haus T/workshop
  event
  # leader ⇧digit threw window 11 to W and followed it.
  world "W" 11 "11 12" T/workshop W
  event
  [ -z "$(cat "$AE/jumped")" ]
}

@test "walking off a still-populated page never hops" {
  world "T/haus" 11 "11 12 20" T/haus T/workshop W
  event
  world "W" 20 "11 12 20" T/haus T/workshop W
  event
  [ -z "$(cat "$AE/jumped")" ]
}

@test "emptied in place still lands on the family" {
  world "T/haus" 11 "11 12 20" T/haus T/workshop W
  event
  world "T/haus" "" "12 20" T/workshop W
  event
  [ "$(cat "$AE/jumped")" = "T/workshop" ]
}

#!/usr/bin/env bats
# Hermetic tests for the fullscreen ON take — modules/windows/scripts/
# fullscreen-toggle.sh, both the <mod>f binding and the `on <window-id>` form a
# lane's trill fin reaches through terminal/scripts/raise-session.sh
# --fullscreen — plus the flag loop on that side.
#
# Why a suite. Two of the rules the take keeps are invisible when they break.
# The solo-window guard bites later rather than now: fullscreen is a MODE, so
# arming it with one window on the page looks like nothing at all, and the next
# window to open there is born behind it with only the bar's glyph to say why.
# And the take counts the window's OWN page: hand it an id whose raise did not
# land and a version that counted the FOCUSED page would arm the mode against
# some other page's window count, somewhere you are not looking.
#
# The subject is two text queries and one command, so it needs no Mac, no
# window and no tiler: `aerospace` is a recorder behind HAUS_AEROSPACE_BIN
# (a PATH stub would lose to the absolute path a GUI-spawned script carries,
# the same reason test/zmx-rows.bats has HAUS_ZMX_BIN), and the bar's notify
# hook is a second recorder under a temporary HOME.

bats_require_minimum_version 1.5.0

SUBJECT() { printf '%s' "$BATS_TEST_DIRNAME/../modules/windows/scripts/fullscreen-toggle.sh"; }

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.config/sketchybar"
  NOTIFY_LOG="$BATS_TEST_TMPDIR/notify.log"
  AERO_LOG="$BATS_TEST_TMPDIR/aerospace.log"
  export NOTIFY_LOG AERO_LOG
  : >"$NOTIFY_LOG"
  : >"$AERO_LOG"

  cat >"$HOME/.config/sketchybar/aerospace-notify.sh" <<'NOTIFY'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$NOTIFY_LOG"
NOTIFY
  chmod +x "$HOME/.config/sketchybar/aerospace-notify.sh"

  # The desk. `T/haus` holds three windows, `T/solo` holds one, and 58716 is a
  # lane on the busy page. Defaults: nothing is fullscreen yet.
  export AERO_ALL='58716|T/haus
58831|T/haus
58836|T/haus
44630|T/solo'
  export AERO_FOCUSED='58716|false'
  export AERO_FS_STATUS=0

  # Every invocation logged verbatim, so a case can assert what did NOT run as
  # easily as what did — the solo guard has no other tell.
  export HAUS_AEROSPACE_BIN="$BATS_TEST_TMPDIR/aerospace"
  cat >"$HAUS_AEROSPACE_BIN" <<'AERO'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$AERO_LOG"
case "$1" in
  list-windows)
    case "$2" in
      --all) printf '%s\n' "$AERO_ALL" ;;
      --focused) printf '%s\n' "$AERO_FOCUSED" ;;
      --workspace) printf '%s\n' "$AERO_ALL" | grep -c "|$3\$" ;;
    esac
    ;;
  fullscreen)
    # `--fail-if-noop`: nonzero when the window was already in the mode.
    [ "$2" = on ] && exit "$AERO_FS_STATUS"
    ;;
esac
exit 0
AERO
  chmod +x "$HAUS_AEROSPACE_BIN"
}

# notify() is backgrounded, so the subject exits before its child writes. Poll
# for the poke rather than reading once; settle before asserting its absence.
poked() {
  local i
  for i in 1 2 3 4 5 6 7 8 9 10; do
    grep -qx fullscreen "$NOTIFY_LOG" && return 0
    sleep 0.1
  done
  return 1
}
not_poked() {
  sleep 0.4
  [ ! -s "$NOTIFY_LOG" ]
}

# ── `on <window-id>`: what a lane's fin click reaches ───────────────────────

@test "on: company on the page takes the mode and pokes the bar" {
  run "$(SUBJECT)" on 58716
  [ "$status" -eq 0 ]
  grep -qx 'fullscreen on --window-id 58716 --fail-if-noop' "$AERO_LOG"
  poked
}

@test "on: the count is the WINDOW's page, not the focused one" {
  # 58716 lives on T/haus; the recorder would answer a T/solo count as 1.
  run "$(SUBJECT)" on 58716
  grep -qx 'list-windows --workspace T/haus --count' "$AERO_LOG"
}

@test "on: a window alone on its page is left alone" {
  # The visual no-op that arms the mode. Nothing on screen would say it ran.
  run "$(SUBJECT)" on 44630
  [ "$status" -eq 0 ]
  ! grep -q '^fullscreen' "$AERO_LOG"
  not_poked
}

@test "on: a window the tiler has never heard of is nothing to act on" {
  run "$(SUBJECT)" on 99999
  [ "$status" -eq 0 ]
  ! grep -q '^fullscreen' "$AERO_LOG"
  not_poked
}

@test "on: already fullscreen is a noop, and the bar is not poked for it" {
  # The second fin click for the same lane. --fail-if-noop tells them apart.
  AERO_FS_STATUS=1
  run "$(SUBJECT)" on 58716
  [ "$status" -eq 0 ]
  grep -qx 'fullscreen on --window-id 58716 --fail-if-noop' "$AERO_LOG"
  not_poked
}

@test "on: an id that is not digits is declined, not escaped into the sed" {
  run "$(SUBJECT)" on '58716|T/haus'
  [ "$status" -eq 0 ]
  [ ! -s "$AERO_LOG" ]
  run "$(SUBJECT)" on ''
  [ "$status" -eq 0 ]
  [ ! -s "$AERO_LOG" ]
}

@test "on: the take is an explicit on, never the bare toggle" {
  run "$(SUBJECT)" on 58716
  ! grep -qx 'fullscreen --window-id 58716' "$AERO_LOG"
  ! grep -qx 'fullscreen' "$AERO_LOG"
}

# ── no arguments: the <mod>f binding ────────────────────────────────────────

@test "mod-f: a focused window with company takes the mode by its own id" {
  run "$(SUBJECT)"
  [ "$status" -eq 0 ]
  grep -qx 'fullscreen on --window-id 58716 --fail-if-noop' "$AERO_LOG"
  poked
}

@test "mod-f: a focused window alone on its page gets nothing" {
  AERO_FOCUSED='44630|false'
  run "$(SUBJECT)"
  [ "$status" -eq 0 ]
  ! grep -q '^fullscreen' "$AERO_LOG"
  not_poked
}

@test "mod-f: a window already fullscreen gets the OFF take, siblings or no" {
  # The bare toggle, deliberately: this is the way out of a mode a closed
  # sibling left armed, so it must not consult the count.
  AERO_FOCUSED='44630|true'
  run "$(SUBJECT)"
  [ "$status" -eq 0 ]
  grep -qx 'fullscreen' "$AERO_LOG"
  poked
}

@test "mod-f: no focused window at all is nothing to act on" {
  AERO_FOCUSED=''
  run "$(SUBJECT)"
  [ "$status" -eq 0 ]
  ! grep -q '^fullscreen' "$AERO_LOG"
  not_poked
}

# ── the flag that reaches it: raise-session.sh's argument loop ───────────────
# Four callers pass a bare session, one passes --or-open, and lane-focus.sh
# passes --fullscreen. The loop is the one part of that script every existing
# caller runs through, so it is pinned here rather than left to the two callers
# that would fail silently (every one of them redirects both streams away).
flags() { # ARGV…
  eval "$(sed -n '/^or_open=0$/,/^done$/p' \
    "$BATS_TEST_DIRNAME/../modules/terminal/scripts/raise-session.sh")"
  printf '%s %s %s\n' "$or_open" "$fullscreen" "${1:-}"
}

@test "flags: a bare session is what the bar, ⌘F and the palette pass" {
  run flags scruff.haus.lane
  [ "$output" = "0 0 scruff.haus.lane" ]
}

@test "flags: --fullscreen is lane-focus.sh's, and stops at the session" {
  run flags --fullscreen scruff.haus.lane
  [ "$output" = "0 1 scruff.haus.lane" ]
}

@test "flags: --or-open still reads as it did, alone or with the new one" {
  run flags --or-open scruff.haus.lane
  [ "$output" = "1 0 scruff.haus.lane" ]
  run flags --or-open --fullscreen scruff.haus.lane
  [ "$output" = "1 1 scruff.haus.lane" ]
  run flags --fullscreen --or-open scruff.haus.lane
  [ "$output" = "1 1 scruff.haus.lane" ]
}

@test "flags: an unknown leading argument is a session name, not a flag" {
  # Which the charset check below the loop then refuses — a caller passing a
  # flag this script does not know must not silently raise something else.
  run flags --nope scruff.haus.lane
  [ "$output" = "0 0 --nope" ]
}

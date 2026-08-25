#!/bin/bash
# focused-session.sh — "which zmx session is the focused window running?"
#
# The one join between the WINDOW layer (which knows what has focus) and the
# SESSION layer (zmx, which knows what is in it and can read it back).
# Every chord bound outside the terminal needs it: ⌘F searches this window's
# scrollback, ⌘L mines its URLs, ⌘↵ and ⌘N want its directory (lane-cwd.sh
# builds on this).
#
# Two joins, because the two kinds of window carry their identity differently:
#
#   any window  scripts/launch.sh stamps the window id it was given onto the
#               session as a label, and that is the join. The label is refreshed
#               on every attach, so a session reattached into a new window is
#               never stale for longer than that attach. Exact: an id is one
#               window and always its own.
#   a LANE      has no such label — its session is created by `zmx attach`
#               inside the window rather than by launch.sh — but its window
#               TITLE is the session name, because lanes/lane-open.sh spawns it
#               with `open -na --title holt.<repo>.<lane>` and Ghostty treats
#               that as a FORCED title the client inside can't clobber with
#               OSC 2. String equality, nothing to look up.
#
# ── the label is asked FIRST, and that ordering is load-bearing ──────────────
# The title used to win, on the reasoning that it is exact. It is not: Ghostty's
# `--title` is INSTANCE-WIDE configuration, not a property of the one window it
# was spawned for. So every window opened later inside that same Ghostty process
# wears the lane's name too — and scripts/new-window.sh opens windows through
# `tell application "Ghostty"`, which reaches whichever instance macOS routes it
# to. Once every running instance is a lane's (which is the ordinary state of
# this machine after a few spawns), a plain ⌘N terminal is BORN wearing some
# lane's title.
#
# Title-first then answered with that lane's session, and every chord built on
# this file acted on the wrong window: ⌘F searched the agent's scrollback, ⌘N
# and ⌘↵ opened in the agent's checkout. MEASURED 2026-08-23 — a `term.*`
# session created with `start_dir` pointing at a lane worktree three repos away
# from the window it was opened from.
#
# A mistitled plain window still carries its own `window=` label, and a real
# lane still carries no label at all, so asking the label first is right for
# both and the title stays as the fallback it should always have been.
#
# ── two backends, because the tiler is optional ──────────────────────────────
# AeroSpace is the fast path and the default where it exists: `aerospace
# list-windows --focused` is a ~4 ms round trip to a daemon that already tracks
# every window. But windows is a ROOM, and a machine can perfectly well run
# Ghostty, zmx, holt and agents with no tiler at all — on which this file was
# the single reason every chord above went dead, and the reason lanes carried a
# build-time assertion demanding the tiler (modules/terminal/default.nix).
#
# So when there is no `aerospace`, ask GHOSTTY. Its AppleScript API reports
# `frontmost`, the front window's STABLE `id` and its `name` — with no window
# manager, no Accessibility grant and no helper process. On that machine the
# id is the join for BOTH kinds of window, because lanes/lane-open.sh opens
# lanes through the same API rather than as their own process, and stamps the
# id it gets back as `gwindow=`. (The title fallback below still costs
# nothing; it simply has nothing to match there, since a lane spawned that way
# wears the client's own title.)
#
# That single-instance detail is the whole reason the two backends can't be
# mixed: `tell application "Ghostty"` reaches ONE process, so with a lane per
# process — what `open -na` gives the AeroSpace backend — it would cheerfully
# answer for a window that isn't the focused one. lane-open.sh's own note has
# the measurement.
#
# It costs ~150 ms against AeroSpace's ~4 ms, which is why it is the fallback
# and not the default: these chords are pressed from a keystroke.
#
# HAUS_WINDOW_BACKEND=aerospace|ghostty forces one, so a machine that HAS a
# tiler can still feel-test the path a machine without one takes.
#
# stdout: the session name, or nothing. Exit 0 either way — every caller has a
# sensible answer for "no session" and none of them wants an error.
set -u

export PATH="/etc/profiles/per-user/${USER:-$(id -un)}/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/opt/homebrew/bin:/usr/bin:/bin${PATH:+:$PATH}"

command -v zmx >/dev/null 2>&1 || exit 0

backend="${HAUS_WINDOW_BACKEND:-}"
if [ -z "$backend" ]; then
  if command -v aerospace >/dev/null 2>&1; then backend=aerospace; else backend=ghostty; fi
fi

case "$backend" in
  aerospace)
    focused() { aerospace list-windows --focused --format "$1" 2>/dev/null; }

    app="$(focused '%{app-name}')"
    [ "$app" = "Ghostty" ] || exit 0

    title="$(focused '%{window-title}')"
    wid="$(focused '%{window-id}')"
    # The label launch.sh stamps with an AeroSpace window id.
    key=window
    ;;

  ghostty)
    # `tell application "Ghostty"` LAUNCHES Ghostty when it isn't running, so
    # this pgrep is not an optimisation: without it, a chord pressed over
    # Finder would open a terminal nobody asked for and then answer "no
    # session" anyway.
    #
    # `-ix ghostty`: the executable inside the bundle is lower-case, so the
    # capitalised spelling matches NOTHING (terminal/options.nix says so under
    # floatBorder, and lanes/lane-open.sh and scripts/new-window.sh both
    # carried the bug until 2026-08-19 — where it cost two seconds a window
    # rather than the whole answer it would cost here).
    pgrep -ix ghostty >/dev/null 2>&1 || exit 0

    # One osascript, one round trip: frontmost is checked INSIDE the tell, so
    # a window belonging to a Ghostty that isn't in front can never be
    # mistaken for the one under the keystroke. `front window` raises when
    # there are no windows at all (Ghostty running with everything closed),
    # hence the try.
    #
    # The two values are joined OUTSIDE the tell, with `character id 9` rather
    # than AppleScript's `tab` constant, and that is not style: Ghostty's
    # dictionary defines a CLASS called `tab`, which shadows the constant
    # inside its tell block — `& tab &` there compiles happily and puts the
    # three letters t-a-b between the fields. Every value came back as one
    # string, the join matched nothing, and the chord answered "no session"
    # with no error anywhere. Measured 2026-08-19.
    out="$(
      /usr/bin/osascript 2>/dev/null <<'APPLESCRIPT'
set theID to ""
set theName to ""
tell application "Ghostty"
  if not frontmost then return ""
  try
    set w to front window
    set theID to id of w
    set theName to name of w
  on error
    return ""
  end try
end tell
return theID & (character id 9) & theName
APPLESCRIPT
    )"
    rc=$?

    # An empty answer means "Ghostty isn't in front" and is the normal case —
    # silence is right. A non-zero EXIT is a different thing entirely, and the
    # usual cause is one "Don't Allow" on the Automation prompt, which would
    # otherwise kill ⌘F, ⌘L, ⌘↵, ⌘N, ⌘Y and ⌘B on this machine permanently and
    # without a word anywhere. Say it, the way every other script that drives
    # Ghostty over Apple Events says it.
    if [ "$rc" -ne 0 ]; then
      /run/current-system/sw/bin/haus-notify --source haus.terminal --kind fault --symbol exclamationmark.triangle \
        --title "haus · terminal" \
        --body "couldn't ask Ghostty which window is focused — check Privacy & Security → Automation." >/dev/null 2>&1
      exit 0
    fi
    [ -n "$out" ] || exit 0

    wid="${out%%$'\t'*}"
    title="${out#*$'\t'}"
    # A DIFFERENT label from the AeroSpace one, deliberately: launch.sh stamps
    # both where it can, and two id spaces under one key would resolve to the
    # wrong window exactly when a machine has both. Written by launch.sh for a
    # plain window and by lanes/lane-open.sh for a lane.
    key=gwindow
    ;;

  *)
    exit 0
    ;;
esac

# One `zmx ls` for both joins: it is a socket round-trip per session, and these
# chords are pressed from a keystroke.
printf '%s' "$(zmx ls 2>/dev/null)" | awk -F'\t' -v want="$title" -v wid="$wid" -v key="$key" '
  {
    name = ""; win = ""
    for (i = 1; i <= NF; i++) {
      p = index($i, "=")
      if (p == 0) continue
      k = substr($i, 1, p - 1); gsub(/^[ \t]+|[ \t]+$/, "", k)
      # zmx marks the row you are ATTACHED to in its first field
      # ("-> ** name=..."), gluing the marker onto that key. Strip
      # anything before the key proper or the session you are
      # sitting in is the one row that never matches.
      sub(/^[^A-Za-z_]*/, "", k)
      # Only up to the FIRST "=": a label value can carry its own.
      if (k == "name") name = substr($i, p + 1)
      if (k == key)    win  = substr($i, p + 1)
    }
    if (name == "") next
    # Label first — see the note at the top of this file on why the title
    # cannot be trusted to be unique.
    if (wid != "" && win == wid) { print name; exit }
    if (name == want) bytitle = name
  }
  END { if (bytitle != "") print bytitle }
'
exit 0

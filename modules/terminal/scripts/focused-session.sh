#!/bin/bash
# focused-session.sh — "which zmx session is the focused window running?"
#
# The one join between the WINDOW layer (AeroSpace, which knows what has focus)
# and the SESSION layer (zmx, which knows what is in it and can read it back).
# Every chord bound outside the terminal needs it: ⌘F searches this window's
# scrollback, ⌘L mines its URLs, ⌘↵ and ⌘N want its directory (lane-cwd.sh
# builds on this).
#
# Two joins, tried in order, because the two kinds of window carry their
# identity differently:
#
#   a LANE      the window title IS the session name. lanes/lane-open.sh spawns
#               it with `open -na --title holt.<repo>.<lane>`, which Ghostty
#               treats as a FORCED title — the client inside cannot clobber it
#               with OSC 2. String equality, nothing to look up.
#   any other   the title is whatever the program inside last emitted, which is
#               the right answer for a window switcher and useless as a key. So
#               scripts/launch.sh stamps the AeroSpace window id it tiled onto
#               the session as a `window=` label, and that is the join. The
#               label is refreshed on every attach, so a session reattached into
#               a new window is never stale for longer than that attach.
#
# stdout: the session name, or nothing. Exit 0 either way — every caller has a
# sensible answer for "no session" and none of them wants an error.
set -u

export PATH="/etc/profiles/per-user/${USER:-$(id -un)}/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/opt/homebrew/bin:/usr/bin:/bin${PATH:+:$PATH}"

command -v zmx >/dev/null 2>&1 || exit 0

focused() { aerospace list-windows --focused --format "$1" 2>/dev/null; }

app="$(focused '%{app-name}')"
[ "$app" = "Ghostty" ] || exit 0

title="$(focused '%{window-title}')"
wid="$(focused '%{window-id}')"

# One `zmx ls` for both joins: it is a socket round-trip per session, and these
# chords are pressed from a keystroke.
printf '%s' "$(zmx ls 2>/dev/null)" | awk -F'\t' -v want="$title" -v wid="$wid" '
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
      if (k == "name")   name = substr($i, p + 1)
      if (k == "window") win  = substr($i, p + 1)
    }
    if (name == "") next
    if (name == want) { print name; exit }
    if (wid != "" && win == wid) byid = name
  }
  END { if (byid != "") print byid }
'
exit 0

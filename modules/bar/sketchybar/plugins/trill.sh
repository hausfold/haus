#!/bin/bash
# trill.sh — the trill pill: a bell that opens the notification inbox
# (hausfold.co/docs/haus/rooms/bar-widgets).
#
# WHY A PILL AT ALL, when Trill.app already installs a menu-bar item of its own
# with an Inbox row in it: `haus.bar.enable` sets `_HIHideMenuBar`
# (modules/core), because this bar is meant to REPLACE macOS's. So on a Mac
# running this desktop trill's own status item is behind a hover-reveal, and
# the inbox — the window that holds every notification that was routed to it
# rather than put on screen — has no always-visible way in. This is that way in.
#
# It renders state and relays clicks and does nothing else. Every verb, flag and
# exit code below is trill's.
# widget: interval = 30

BAR_ITEM=trill
source "$HOME/.config/sketchybar/barlib.sh"

# Resolve trill. Trill.app IS the CLI — one signed executable serves the daemon
# and every verb — so "is trill installed" is "is that binary on this disk", and
# it is a RUNTIME fact: trill is not a haus flake input and no room installs it,
# so a nix-time answer would be wrong on both kinds of Mac.
#
# $TRILL_APP first, so a person testing a branch build can point at it; then a
# `trill` on the system profile, which is where core's shim puts the name —
# modules/core ships modules/core/trill.sh unconditionally, so on any machine
# running this bar that candidate answers and the rest of the list never runs.
# It is kept anyway because this file is also read on a Mac mid-rebuild, where
# the profile can be a generation behind the plugin dir; then the two places
# every install source puts the bundle, /Applications first for
# modules/core/trill.sh's reason (a dev build in ~/Applications must not outrank
# the pinned release).
resolve_trill() {
    local candidate
    for candidate in \
        "${TRILL_APP:-}/Contents/MacOS/Trill" \
        "/run/current-system/sw/bin/trill" \
        "/Applications/Trill.app/Contents/MacOS/Trill" \
        "${HOME:-}/Applications/Trill.app/Contents/MacOS/Trill"; do
        [ -x "$candidate" ] && { printf '%s' "$candidate"; return 0; }
    done
    return 1
}

# No trill on this Mac: draw NOTHING (`pill --hide`, the drawing=off/
# updates=on pairing the runtime owns). It comes back by itself the moment
# the app lands — the item's own `updates=on` style keeps this tick running
# while the pill is hidden, which is the other half of that door.
#
# Installed, daemon up vs installed, daemon down — the same distinction the
# elgato and harvest pills draw: "nothing is running" and "I can't ask" look
# identical if only one of them is drawn.
fetch() {
    local trill
    trill=$(resolve_trill) || { emit present=0; return 0; }
    if "$trill" ping >/dev/null 2>&1; then
        emit present=1 up=1
    else
        emit present=1 up=0
    fi
}

render() {
    if [ "$present" != 1 ]; then
        pill --hide
        return 0
    fi
    # No --icon: the bell is a fixed identity glyph set once at --add
    # time in the Nix style, and this widget only ever touches its
    # colour and whether it draws at all — exactly what the hand-written
    # pill did.
    if [ "$up" = 1 ]; then
        pill --label "" --tone text
    else
        pill --label "" --tone mute
    fi
}

# open_inbox [scope…] — every click lands here with a different scope: plain
# is the whole inbox, right-click (and ⌥-click, which sketchybar reports the
# same way) narrows to the asks — the questions parked on trill's ledge that
# are still waiting on an answer.
open_inbox() {
    local trill
    trill=$(resolve_trill) || return 0
    "$trill" inbox "$@" >/dev/null 2>&1
    # 2 is "daemon unreachable" for every trill verb but `ask`, which spends the
    # low numbers on pill indices and reports its own failures up at 69/70/75.
    # It is the ONE code worth acting on: 1 (bad usage) and 3 (refused) both
    # mean trill ran and had something to say, and starting the app would not
    # change either answer.
    if [ $? -eq 2 ]; then
        # The app is on disk, so the honest response to a click is to start it
        # and ask again rather than fail quietly at somebody who just pressed a
        # button. By BUNDLE ID, not by the path we resolved: that path may be a
        # `trill` on the system profile rather than anything inside a bundle,
        # and `open -a` on a bare executable fails. Backgrounded — a click
        # script that sleeps is a bar that stops redrawing.
        (
            /usr/bin/open -g -b com.hausfold.trill >/dev/null 2>&1 || exit 0
            # Five seconds of asking, then give up silently.
            for _ in 1 2 3 4 5 6 7 8 9 10; do
                /bin/sleep 0.5
                "$trill" inbox "$@" >/dev/null 2>&1 && break
            done
        ) &
    fi
    # A click can change whether the daemon answers (it may just have
    # started it) — refresh so the pill's own tint reflects that immediately
    # rather than waiting out the interval.
    barlib_tick
}

on_click() { open_inbox; }
on_right_click() { open_inbox --asks; }
on_alt_click() { open_inbox --asks; }

barlib_main "$@"

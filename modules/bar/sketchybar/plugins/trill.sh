#!/bin/bash
# The trill pill: a bell that opens the notification inbox.
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

source "$HOME/.config/sketchybar/colors.sh"
# $SB — which bar this pill lives on. haus.bar.bottom.items can move it to the
# second (bottom) bar, and the two instances are addressed by different
# binaries; a bare `sketchybar` would always mean the menu bar one.
BAR_ITEM=trill
source "$HOME/.config/sketchybar/bar.sh"

# Resolve trill the way core's own shim does (modules/core/trill.sh, which puts
# the name on PATH as a wrapper): the shim first when the desktop ships one,
# then the two places every install source puts the bundle, then $TRILL_APP for
# a person testing a branch build. Trill.app IS the CLI — one signed executable
# serves the daemon and every verb — so "is trill installed" is "is that binary
# on this disk", and it is a RUNTIME fact: trill is not a haus flake input and
# no room installs it, so a nix-time answer would be wrong on both kinds of Mac.
#
# Resolving here rather than only calling the shim is what makes the pill work
# before, during and after that shim exists. If the shim is ever the only
# supported path, this loop is what gets deleted, not something that has to be
# kept in step with it.
TRILL=""
for candidate in \
    "/run/current-system/sw/bin/trill" \
    "${TRILL_APP:-}/Contents/MacOS/Trill" \
    "${HOME:-}/Applications/Trill.app/Contents/MacOS/Trill" \
    "/Applications/Trill.app/Contents/MacOS/Trill"
do
    # An unset $TRILL_APP collapses to a path that cannot exist, so the -x test
    # is the whole guard: no candidate needs a second one.
    [ -x "$candidate" ] && { TRILL="$candidate"; break; }
done

# No trill on this Mac: draw NOTHING. The pill is opt-in, so somebody asked for
# it — but a control that opens an app you don't have has nothing to offer and
# no state to report, and a permanently dim bell is a bar element you learn to
# read past. It reappears by itself the moment the app lands, because the pill
# still ticks on its update_freq with drawing off.
if [ -z "$TRILL" ]; then
    "$SB" --set "$NAME" drawing=off
    exit 0
fi

if [ "${SENDER:-}" = "mouse.clicked" ]; then
    # Right-click (and ⌥-click, which sketchybar reports the same way) narrows
    # to the asks: the questions parked on trill's ledge that are still waiting
    # on an answer. Left-click is the whole inbox.
    # MODIFIER arrives as a COMBINATION ("alt", "cmd,alt", or the literal
    # "none" on a plain click), hence the glob rather than an equality test.
    SCOPE=()
    case "${BUTTON:-left}:${MODIFIER:-none}" in
        right:* | *:*alt*) SCOPE=(--asks) ;;
    esac

    # 69 is trill's "daemon unreachable". The app is on disk, so the honest
    # response to a click is to start it and ask again rather than to fail
    # quietly at somebody who just pressed a button. Backgrounded: a click
    # script that sleeps is a bar that stops redrawing.
    if ! "$TRILL" inbox "${SCOPE[@]}" >/dev/null 2>&1; then
        (
            /usr/bin/open -a "${TRILL%/Contents/MacOS/Trill}" >/dev/null 2>&1 || exit 0
            # Five seconds of asking, then give up silently: the app is starting
            # or it isn't, and a notifier that notifies you about the notifier
            # failing to start is worse than the click that did nothing.
            for _ in 1 2 3 4 5 6 7 8 9 10; do
                /bin/sleep 0.5
                "$TRILL" inbox "${SCOPE[@]}" >/dev/null 2>&1 && break
            done
        ) &
    fi
fi

# Installed, daemon up vs installed, daemon down — the same distinction the
# elgato and harvest pills draw, and for the same reason: "nothing is running"
# and "I can't ask" look identical if only one of them is drawn.
if "$TRILL" ping >/dev/null 2>&1; then
    "$SB" --set "$NAME" icon.color="$TEXT"
else
    "$SB" --set "$NAME" icon.color="$OVERLAY0"
fi

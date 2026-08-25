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

# Resolve trill. Trill.app IS the CLI — one signed executable serves the daemon
# and every verb — so "is trill installed" is "is that binary on this disk", and
# it is a RUNTIME fact: trill is not a haus flake input and no room installs it,
# so a nix-time answer would be wrong on both kinds of Mac.
#
# $TRILL_APP first, so a person testing a branch build can point at it; then a
# `trill` on the system profile, which is where a future core shim would put the
# name (hausfold/haus#511 adds one — this list is deliberately written to work
# before, during and after that lands, and is what gets deleted if the shim ever
# becomes the only supported path); then the two places every install source
# puts the bundle.
TRILL=""
for candidate in \
    "${TRILL_APP:-}/Contents/MacOS/Trill" \
    "/run/current-system/sw/bin/trill" \
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
# read past. It comes back by itself the moment the app lands: the item block
# carries `updates=on` so this script keeps running while the pill is hidden,
# and the two branches at the bottom set `drawing=on` again. Without EITHER
# half, hiding here would be a one-way door until the next rebuild.
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

    "$TRILL" inbox "${SCOPE[@]}" >/dev/null 2>&1
    # 2 is "daemon unreachable" for every trill verb but `ask`, which spends the
    # low numbers on pill indices and reports its own failures up at 69/70/75.
    # It is the ONE code worth acting on: 1 (bad usage) and 3 (refused) both
    # mean trill ran and had something to say, and starting the app would not
    # change either answer. Anything else is a bad `case` here, not a dead
    # daemon, so the click does nothing rather than launching an app on a guess.
    if [ $? -eq 2 ]; then
        # The app is on disk, so the honest response to a click is to start it
        # and ask again rather than fail quietly at somebody who just pressed a
        # button. By BUNDLE ID, not by the path we resolved: that path may be a
        # `trill` on the system profile rather than anything inside a bundle,
        # and `open -a` on a bare executable fails. Backgrounded — a click
        # script that sleeps is a bar that stops redrawing.
        (
            /usr/bin/open -g -b com.hausfold.trill >/dev/null 2>&1 || exit 0
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
# `drawing=on` on BOTH branches, not just the first time: the pill hides itself
# above when there is no Trill.app, and the block that adds it carries
# `updates=on` precisely so this tick still runs while it is hidden. Turning
# drawing back on here is the other half — without it, installing the app would
# leave a bell that ticks forever and never reappears.
if "$TRILL" ping >/dev/null 2>&1; then
    "$SB" --set "$NAME" drawing=on icon.color="$TEXT"
else
    "$SB" --set "$NAME" drawing=on icon.color="$OVERLAY0"
fi

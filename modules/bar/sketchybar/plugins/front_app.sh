#!/bin/bash

# $BAR_TOP — GENERATED from haus.roster.sketchybar.binPath. The front-app pill is
# a menu-bar item, so it is always the TOP bar's mach service; naming the binary
# here by hand is what §5.4 is about.
source "$HOME/.config/sketchybar/bar.sh"

# The app name, from $INFO on a switch and from lsappinfo on the cold paint —
# never from System Events, whose Automation prompt this plugin used to put on
# screen on every app switch of a fresh install, and whose read is what jammed
# every other Apple event on the machine while that prompt sat unanswered. The
# whole story is front_app_lib.sh's header.
# shellcheck source=./front_app_lib.sh
source "$HOME/.config/sketchybar/plugins/front_app_lib.sh"
FRONT_APP=$(front_app_name)

# While AeroSpace's resize or navigate mode is armed (see resize_mode.sh /
# navigate_mode.sh), keep that mode's glyph appended — moving focus repaints this
# label, which would otherwise drop it. fa-arrows-h (U+F07E) for resize,
# fa-arrows (U+F047) for navigate; keep in sync with those scripts.
if [ -f /tmp/sketchybar_resize_state ]; then
    GLYPH=$(printf '\xEF\x81\xBE')
    "$BAR_TOP" --set "$NAME" label="$FRONT_APP $GLYPH"
elif [ -f /tmp/sketchybar_navigate_state ]; then
    GLYPH=$(printf '\xEF\x81\x87')
    "$BAR_TOP" --set "$NAME" label="$FRONT_APP $GLYPH"
else
    "$BAR_TOP" --set "$NAME" label="$FRONT_APP"
fi

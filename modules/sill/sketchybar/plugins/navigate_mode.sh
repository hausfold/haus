#!/bin/bash
# navigate_mode.sh on|off
#
# Indicator for AeroSpace's `navigate` mode (entered via the launch leader's
# arrows). Recolors the front-app pill catppuccin sky and appends a four-way
# move glyph to the end of the app name. `off` restores the normal lavender pill
# and the bare app name. Mirrors resize_mode.sh (see it for the front_app pill
# it recolors).
#
# A state file (STATE) records that the mode is armed: front_app.sh reads it so
# that moving focus around the workspace (which fires front_app_switched and
# repaints the label) keeps the glyph instead of dropping it. Because navigate
# mode's whole job is moving focus, that repaint fires constantly — the state
# check is what keeps the pill from flickering back to normal mid-navigate.

export PATH="/run/current-system/sw/bin:/opt/homebrew/bin:/usr/bin:/bin:$PATH"

STATE="/tmp/sketchybar_navigate_state"    # present == armed
SIBLING="/tmp/sketchybar_resize_state"    # resize_mode.sh's state — `on` clears
                                          # it so a resize→navigate hop is ONE
                                          # script call (two async calls would
                                          # race on the same pill)

source "$HOME/.config/sketchybar/colors.sh"

# fa-arrows (U+F047), four-way move, as raw UTF-8 bytes — /bin/bash is 3.2,
# whose printf has no \u/\U; \xHH works. Keep in sync with front_app.sh.
GLYPH=$(printf '\xEF\x81\x87')

front_app() {
    osascript -e 'tell application "System Events" to get name of first application process whose frontmost is true'
}

case "$1" in
    on)
        : > "$STATE"
        rm -f "$SIBLING"
        # Haus-tour hook — one stat when no tour is mid-flight (plugins/tour.sh).
        { [ -f "$HOME/.local/state/haus/tour" ] && "$HOME/.config/sketchybar/plugins/tour.sh" event navigate; } >/dev/null 2>&1 &
        sketchybar --set front_app background.color=$SKY label.color=$BASE \
                                    label="$(front_app) $GLYPH"
        ;;
    off)
        rm -f "$STATE"
        sketchybar --set front_app background.color=$LAVENDER label.color=$BASE \
                                    label="$(front_app)"
        ;;
    *)
        echo "usage: $0 on|off" >&2; exit 1 ;;
esac

#!/bin/bash
# The focus pill: bell = listening, struck bell on mauve = quiet. All logic
# lives in the focus engine (modules/focus → ~/.local/bin/focus); this script
# only relays clicks and renders state. Kept honest three ways: the engine
# fires focus_change after its own toggles, the focus-watcher launchd agent
# fires it when the Focus DB changes (Control Center / iPhone), and
# update_freq polls as a backstop.

source "$HOME/.config/sketchybar/colors.sh"
source "$HOME/.config/sketchybar/bar.sh"

FOCUS="$HOME/.local/bin/focus"

if [ "${SENDER:-}" = "mouse.clicked" ]; then
    # On failure (no Accessibility grant yet) the engine posts its own
    # "run focus doctor" notification — nothing to handle here.
    "$FOCUS" toggle || true
fi

if [ "$("$FOCUS" status 2>/dev/null)" = "on" ]; then
    "$SB" --set "$NAME" \
        icon="󰂛" \
        icon.color=$BASE \
        background.color=$MAUVE \
        label.drawing=off
else
    "$SB" --set "$NAME" \
        icon="󰂚" \
        icon.color=$TEXT \
        background.color=$SURFACE0 \
        label.drawing=off
fi

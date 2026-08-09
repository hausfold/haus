#!/bin/bash
# The hush pill: bell = listening, struck bell on mauve = hushed. All logic
# lives in the hush engine (modules/hush → ~/.local/bin/hush); this script
# only relays clicks and renders state. Kept honest three ways: the engine
# fires hush_change after its own toggles, the hush-watcher launchd agent
# fires it when the Focus DB changes (Control Center / iPhone), and
# update_freq polls as a backstop.

source "$HOME/.config/sketchybar/colors.sh"
source "$HOME/.config/sketchybar/bar.sh"

HUSH="$HOME/.local/bin/hush"

if [ "${SENDER:-}" = "mouse.clicked" ]; then
    # On failure (no Accessibility grant yet) the engine posts its own
    # "run hush doctor" notification — nothing to handle here.
    "$HUSH" toggle || true
fi

if [ "$("$HUSH" status 2>/dev/null)" = "on" ]; then
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

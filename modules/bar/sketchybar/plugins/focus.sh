#!/bin/bash
# The focus pill: a crescent moon = listening, moon-and-stars on mauve = quiet.
# All logic lives in the focus engine (modules/focus → ~/.local/bin/focus); this
# script only relays clicks and renders state. Kept honest three ways: the
# engine fires focus_change after its own toggles, the focus-watcher launchd
# agent fires it when the Focus DB changes (Control Center / iPhone), and
# update_freq polls as a backstop.
#
# It was a bell (md-bell / md-bell_off) until plugins/trill.sh wanted one. A
# bell is what a notification IS, so it belongs to the pill that opens the
# notification inbox; a moon is what every OS that ships a Do-Not-Disturb
# switch draws on it, macOS's own Control Center included. Two glyphs rather
# than one recoloured, because the pill has always been readable in the corner
# of an eye where a mauve pill and a surface one are two grey blobs.

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
        icon="󰖔" \
        icon.color=$BASE \
        background.color=$MAUVE \
        label.drawing=off
else
    "$SB" --set "$NAME" \
        icon="󰽥" \
        icon.color=$TEXT \
        background.color=$SURFACE0 \
        label.drawing=off
fi

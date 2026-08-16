#!/bin/bash

# $SB — the bar this pill lives on. It can be either one: the readouts are
# movable via haus.bar.bottom.items, and a bare `sketchybar` here would keep
# updating a top-bar item that no longer exists. See bar.sh.
source "$HOME/.config/sketchybar/bar.sh"

# Get volume level
VOLUME=$(osascript -e 'output volume of (get volume settings)')
MUTED=$(osascript -e 'output muted of (get volume settings)')

# Determine icon
if [ "$MUTED" = "true" ]; then
    ICON="󰖁"
    LABEL="Muted"
elif [ "$VOLUME" -gt 66 ]; then
    ICON="󰕾"
    LABEL="${VOLUME}%"
elif [ "$VOLUME" -gt 33 ]; then
    ICON="󰖀"
    LABEL="${VOLUME}%"
elif [ "$VOLUME" -gt 0 ]; then
    ICON="󰕿"
    LABEL="${VOLUME}%"
else
    ICON="󰖁"
    LABEL="0%"
fi

# Update the bar item
"$SB" --set $NAME \
    icon="$ICON" \
    label="$LABEL"

#!/bin/zsh

[ -f "$HOME/.config/sketchybar/clock_config.sh" ] && source "$HOME/.config/sketchybar/clock_config.sh"

MODE="${SILL_CLOCK_MODE:-full}"

if [ "$MODE" = "compact" ]; then
    DAY=$(date '+%a')
    DATE=$(date '+%d/%m' | sed 's/^0//; s/\/0/\//')
    TIME=$(date '+%l:%M' | tr -d ' ')
    /opt/homebrew/bin/sketchybar --set $NAME \
        icon="" \
        icon.padding_left=0 \
        icon.padding_right=0 \
        label="${DAY} ${DATE} ${TIME}"
else
    DATE=$(date '+%a %b %d')
    TIME=$(date '+%I:%M %p')
    ICON=$(printf "\uf073")

    # Update the bar item
    /opt/homebrew/bin/sketchybar --set $NAME \
        icon="$ICON" \
        icon.padding_left=8 \
        icon.padding_right=4 \
        label="$DATE  $TIME"
fi
